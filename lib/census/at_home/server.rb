# frozen_string_literal: true

require "json"
require "sinatra/base"
require "rack/attack"

module Census
  module AtHome
    # The HTTP face of the coordinator: four JSON endpoints, no views, no
    # sessions. Everything that decides anything lives in Coordinator; this
    # class only speaks HTTP, so it can be swapped for Rails the day the
    # volunteer portal needs accounts.
    #
    # Generic web risks are handled here (body caps, rate limiting, JSON
    # shape); domain risks (submission size, verification cost) are handled
    # by SubmissionGuard and Coordinator, because no framework knows what a
    # plausible tiling certificate looks like.
    # The counter store Rack::Attack expects, minus the Rails dependency:
    # per-key hit counts in a bounded, self-expiring hash.
    class MemoryStore
      def initialize
        @counts = {}
        @mutex = Mutex.new
      end

      def increment(key, amount = 1, options = {})
        expires_in = options[:expires_in].to_i
        @mutex.synchronize do
          @counts.delete_if { |_, (_, expiry)| expiry < Process.clock_gettime(Process::CLOCK_MONOTONIC) }
          count, expiry = @counts[key]
          expiry = Process.clock_gettime(Process::CLOCK_MONOTONIC) + expires_in if expiry.nil? || expiry < Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @counts[key] = [(count || 0) + amount, expiry]
          @counts[key].first
        end
      end

      def read(key) = @mutex.synchronize { @counts[key]&.first }
      def write(key, value, options = {}) = @mutex.synchronize { @counts[key] = [value, Process.clock_gettime(Process::CLOCK_MONOTONIC) + options[:expires_in].to_i] }
      def delete(key) = @mutex.synchronize { @counts.delete(key) }
    end

    class Server < Sinatra::Base
      MAX_BODY_BYTES = 5 * 1024 * 1024

      # Responses this API can give. Named so the reader never has to
      # remember which number means what.
      BAD_REQUEST = 400
      NOT_FOUND = 404
      PAYLOAD_TOO_LARGE = 413
      TOO_MANY_REQUESTS = 429

      # Generous enough that a client leasing, solving, and submitting in a
      # tight loop never trips it; tight enough that a runaway or a flood
      # gets slowed down. Fifty clients on the coordinator's own machine are
      # one IP, so a campaign there raises it through the environment.
      REQUESTS_PER_PERIOD = Integer(ENV.fetch("AT_HOME_THROTTLE_LIMIT", 120))
      THROTTLE_PERIOD_SECONDS = 60

      class << self
        attr_accessor :coordinator
      end

      configure do
        set :show_exceptions, false
        set :raise_errors, false
        set :logging, false
        disable :protection

        # Volunteers reach this by IP or whatever hostname the deployment
        # answers to, so host authorization is off by default — Sinatra 4
        # would otherwise 403 every remote client in production. Set
        # AT_HOME_HOSTS to a comma-separated list to restrict it.
        set :host_authorization, { permitted_hosts: ENV.fetch("AT_HOME_HOSTS", "").split(",") }
      end

      use Rack::Attack

      # In-process counters: one coordinator, so throttling needs no shared
      # store. Put Redis here (or rate-limit at the proxy) if it ever scales
      # to more than one process.
      Rack::Attack.cache.store = MemoryStore.new
      Rack::Attack.throttle("requests by ip", limit: REQUESTS_PER_PERIOD, period: THROTTLE_PERIOD_SECONDS) { it.ip }
      Rack::Attack.throttled_responder = lambda do |request|
        # Abuse is an operational event with no home in the database, so it
        # goes to the log where an operator can see it.
        warn <<~THROTTLED
          #{Time.now.utc.iso8601} THROTTLED #{request.ip} #{request.request_method} #{request.path}
        THROTTLED

        [TOO_MANY_REQUESTS, { "Content-Type" => "application/json" }, [%({"error":"slow down"}\n)]]
      end

      before do
        content_type :json
        halt(PAYLOAD_TOO_LARGE, json(error: "payload too large")) if request.content_length.to_i > body_cap
      end

      post "/register" do
        body = parse_body
        json(client: coordinator.register(handle: require_field(body, :handle),
                                          display_name: body[:display_name],
                                          contact: body[:contact]))
      end

      # The reply carries any proofs owed. A client polls rather than listens,
      # so a request for one rides the request it was already going to make.
      post "/lease" do
        body = parse_body
        client_id = Integer(require_field(body, :client_id))

        unit = coordinator.lease(client_id:)
        reply = { unit:, wanted_proofs: coordinator.wanted_proofs(client_id:) }
        # No unit because the basin is full is different from no unit because
        # the queue is empty: the client should wait, not stop.
        reply[:retry_after] = coordinator.retry_after if unit.nil? && !coordinator.faucet_open?
        json(reply)
      end

      # Proof bytes, not JSON. A DRAT proof is binary and runs to megabytes, so
      # it arrives as a raw body under the digest it is supposed to hash to.
      post "/proof/:sha256" do
        digest = params[:sha256].to_s
        halt(BAD_REQUEST, json(error: "malformed digest")) unless digest.match?(Coordinator::DIGEST)

        bytes = request.body.read(coordinator.max_proof_bytes + 1).to_s
        halt(PAYLOAD_TOO_LARGE, json(error: "proof too large")) if bytes.bytesize > coordinator.max_proof_bytes

        json(coordinator.deliver_proof(sha256: digest, bytes:))
      end

      post "/results" do
        body = parse_body
        json(coordinator.submit(unit_id: Integer(require_field(body, :unit_id)),
                                client_id: Integer(require_field(body, :client_id)),
                                verdict: String(require_field(body, :verdict)),
                                payload: body[:payload] || {},
                                seconds: body[:seconds]))
      end

      # The formula a cube unit refers to. Streamed rather than read into
      # memory: these run to megabytes, and many volunteers may want the same
      # one at once. Cacheable forever, since a formula never changes.
      get "/cnf/:unit_id" do
        path = coordinator.formula_path(Integer(params[:unit_id]))
        halt(NOT_FOUND, json(error: "no formula for that unit")) unless path

        cache_control :public, max_age: 31_536_000
        send_file path, type: "text/plain"
      end

      get "/status" do
        json(coordinator.status)
      end

      # Domain events (who submitted what, what verified, who was rejected)
      # live in the database, where they are queryable. Crashes do not, so
      # they go to the log — otherwise a bug or a database outage would
      # reach a volunteer as a bare 400 and reach us as nothing at all.
      error do
        exception = env["sinatra.error"]
        warn <<~ERROR
          #{Time.now.utc.iso8601} ERROR #{request.request_method} #{request.path}
            #{exception.class}: #{exception.message}
            #{exception.backtrace&.first(5)&.join("\n    ")}
        ERROR

        status BAD_REQUEST
        json(error: exception.message)
      end

      private

      def coordinator = self.class.coordinator

      # JSON bodies stay small. A proof is the one thing allowed to be big, and
      # only because it cannot be anything else.
      def body_cap = request.path.start_with?("/proof") ? coordinator.max_proof_bytes : MAX_BODY_BYTES

      def parse_body
        raw = request.body.read(MAX_BODY_BYTES + 1).to_s
        halt(PAYLOAD_TOO_LARGE, json(error: "payload too large")) if raw.bytesize > MAX_BODY_BYTES
        return {} if raw.empty?

        parsed = JSON.parse(raw, symbolize_names: true)
        raise ArgumentError, "body must be a JSON object" unless parsed.is_a?(Hash)

        parsed
      end

      def require_field(body, key)
        body.fetch(key) { raise ArgumentError, "missing #{key}" }
      end

      def json(payload) = "#{JSON.generate(payload)}\n"
    end
  end
end
