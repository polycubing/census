# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "net/http"
require "tempfile"
require "uri"

module Census
  module AtHome
    # The volunteer half: ask for a unit, solve it locally, hand back the
    # answer, repeat. Holds no census state and needs no trust in either
    # direction — the coordinator re-verifies everything it returns.
    # Raised for responses worth retrying (throttled, or the coordinator
    # having a bad moment) as opposed to responses that are our own fault.
    class TransientResponse < StandardError; end

    class Client
      # A coordinator can restart, redeploy, or briefly vanish; none of that
      # should cost a volunteer their work. Transient failures are retried
      # with capped backoff — including the submission of an already-solved
      # unit, which is the one thing genuinely expensive to lose.
      TRANSIENT_ERRORS = [
        Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH,
        Errno::EPIPE, EOFError, SocketError, Net::OpenTimeout, Net::ReadTimeout
      ].freeze
      RETRY_DELAYS = [1, 2, 5, 10, 20, 30, 60].freeze

      # Responses meaning "not now" rather than "you asked wrongly".
      TOO_MANY_REQUESTS = 429
      SERVER_ERROR_FLOOR = 500

      # Where refutations are kept. A proof is named by its own digest, so the
      # same refutation written twice lands on the same file, and the
      # coordinator can ask for one by the hash it was told.
      DEFAULT_PROOFS = "proofs"

      # Where fetched formulas are cached, keyed by digest. Thousands of cube
      # units can share one formula, so it is downloaded once and reused.
      DEFAULT_FORMULAS = "formulas"

      # How long a volunteer spends on one cube before handing it back as too
      # hard. An unfinished cube is not a failure: the coordinator halves it
      # and the work goes on, so a short lease beats a heroic one.
      DEFAULT_CUBE_TIMEOUT = 3600

      def initialize(url:, handle:, display_name: nil, contact: nil, report: nil, give_up_after: nil,
                     proofs: DEFAULT_PROOFS, formulas: DEFAULT_FORMULAS, cube_timeout: DEFAULT_CUBE_TIMEOUT, disk_floor_bytes: nil)
        @base = URI(url)
        @handle = handle
        @display_name = display_name
        @contact = contact
        @report = report
        @give_up_after = give_up_after
        @proofs = proofs
        @formulas = formulas
        @cube_timeout = cube_timeout
        @disk_floor_bytes = disk_floor_bytes
        @client_id = nil
      end

      def register
        response = post("/register", { handle:, display_name:, contact: })
        @client_id = response && response[:client][:id]
      end

      # Runs until the queue is empty (or limit units are done). Returns a
      # tally of what happened, for the caller to print. A `stopped` entry
      # means the coordinator went away and did not come back.
      def run(limit: nil, idle_sleep: 5, once: false)
        tally = Hash.new(0)
        register unless client_id
        return tally.merge("stopped" => 1) unless client_id

        loop do
          # The volunteer's own limit: no new work while its disk is under
          # the floor it set. Nothing the hub can know for it.
          if disk_floor_bytes && (free = Disk.free_bytes(File.exist?(proofs) ? proofs : File.dirname(File.expand_path(proofs)))) &&
             free < disk_floor_bytes
            report&.call("own disk has #{free / 1_000_000} MB free, under the floor, waiting")
            sleep(idle_sleep * 6)
            next
          end

          lease = post("/lease", { client_id: })
          break tally["stopped"] = 1 unless lease

          hand_over(lease[:wanted_proofs], tally)
          discard(lease[:discard_proofs], tally)

          unit = lease[:unit]
          unless unit
            # The coordinator's basin is full. Work remains, so wait as told,
            # even under --once.
            if lease[:retry_after]
              report&.call("coordinator asks for a #{lease[:retry_after]}s pause")
              sleep(lease[:retry_after])
              next
            end

            break if once

            report&.call("no work available")
            sleep(idle_sleep)
            next
          end

          verdict, payload, seconds = solve(unit)
          answer = post("/results", { unit_id: unit[:id], client_id:, verdict:, payload:, seconds: })
          unless answer
            # The work is done but unreportable; the lease will expire and
            # the unit returns to the queue for someone else.
            report&.call("#{unit[:shape_id]}  #{verdict}  UNREPORTED — coordinator unreachable")
            break tally["stopped"] = 1
          end

          tally[answer[:accepted] ? "accepted" : "rejected"] += 1
          tally[verdict] += 1
          report&.call("#{unit[:shape_id]}  #{verdict}  #{answer[:accepted] ? 'accepted' : "REJECTED (#{answer[:note]})"}  #{seconds}s")
          break if limit && tally["accepted"] + tally["rejected"] >= limit

          # Whatever killed the solver (a full disk, usually) is probably
          # still true a second later. Give it half a minute.
          sleep(idle_sleep * 6) if verdict == "error"
        end
        tally
      end

      private

      attr_reader :base, :client_id, :contact, :cube_timeout, :disk_floor_bytes, :display_name, :formulas, :give_up_after,
                  :handle, :proofs, :report

      # A solver that dies (a full disk, a kill, a bad build) is reported as
      # an error, which the coordinator turns into a released unit for someone
      # else. It must not take the client down with it: ten of twelve clients
      # once died in the same minute because kissat could not flush a proof.
      def solve(unit)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        verdict, payload = begin
          case unit[:kind]
          when "shape" then solve_shape(unit)
          when "cube" then solve_cube(unit)
          else ["error", { note: "unknown unit kind #{unit[:kind]}" }]
          end
        rescue StandardError => error
          report&.call("#{unit[:shape_id]}  solver failed: #{error.message.lines.first.to_s.strip[0, 160]}")
          ["error", { note: error.message[0, 500] }]
        end
        [verdict, payload, (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(2)]
      end

      def solve_shape(unit)
        shape = Polycube.new(cells: unit[:cells])
        budgets = unit[:budgets] || {}
        certificate = BoxSearch.new(shape:, max_volume: budgets.fetch(:box_max_volume, BoxSearch::DEFAULT_MAX_VOLUME)).certificate ||
                      TorusSearch.new(shape:, max_index: budgets.fetch(:torus_max_index, TorusSearch::DEFAULT_MAX_INDEX)).certificate
        return ["exhausted", { budgets: }] unless certificate

        ["tiler", { certificate: }]
      end

      # A refutation is only worth its proof, so one is always written. On SAT
      # the proof is meaningless and goes away with the tempfile; on UNSAT it is
      # kept under its own digest and that digest is what gets reported.
      def solve_cube(unit)
        cnf_path = formula_for(unit)
        return ["error", { note: "formula unavailable" }] unless cnf_path

        Tempfile.create(["census", ".drat"]) do |file|
          model = SAT::Kissat.solve_cube(cnf_path:, cube: unit[:cube], proof_path: file.path,
                                         timeout: cube_timeout)

          # Handed back rather than abandoned: the coordinator splits it.
          return ["exhausted", { cube: unit[:cube], seconds: cube_timeout }] if model == :undecided
          return ["sat", { model: model.to_a }] if model

          ["unsat", { cube: unit[:cube], proof: kept(SAT::Proof.of(file.path)).to_h }]
        end
      end

      # The formula lives on the coordinator, not here. Fetched once per
      # formula and cached by digest, because a shape split into thousands of
      # cubes hands out thousands of units that all refer to the same one.
      #
      # Written under a temporary name and renamed into place, because
      # several clients on one machine share the cache, and one of them
      # reading a formula another is still writing hands kissat a truncated
      # file. Rename is atomic, so the cached name either does not exist or
      # holds every byte.
      def formula_for(unit)
        digest = unit[:cnf_sha256]
        cached = File.join(formulas, "#{digest || "unit-#{unit[:id]}"}.cnf")
        return cached if File.exist?(cached)

        bytes = fetch("/cnf/#{unit[:id]}")
        return nil unless bytes

        if digest && Digest::SHA256.hexdigest(bytes) != digest
          report&.call("formula for unit #{unit[:id]} does not match its digest")
          return nil
        end

        FileUtils.mkdir_p(formulas)
        arriving = "#{cached}.#{Process.pid}.arriving"
        File.binwrite(arriving, bytes)
        File.rename(arriving, cached)

        cached
      end

      # Move the proof to its content-addressed home. Rename is atomic, so the
      # coordinator can never be told a digest for a file that is half written.
      def kept(proof)
        FileUtils.mkdir_p(proofs)
        destination = File.join(proofs, "#{proof.sha256}.drat")
        FileUtils.mv(proof.path, destination) unless File.exist?(destination)

        SAT::Proof.of(destination)
      end

      def post(path, body) = deliver(path, JSON.generate(body), "application/json")

      # A proof goes up as raw bytes. Base64 would inflate a hundred megabytes
      # by a third to say nothing extra.
      def post_proof(sha256)
        deliver("/proof/#{sha256}", File.binread(proof_path(sha256)), "application/octet-stream")
      end

      def proof_path(sha256) = File.join(proofs, "#{sha256}.drat")

      # The coordinator asked to see proofs it was previously only told about.
      # Handing them over is what makes the digest more than a gesture, so it
      # happens before taking more work. Public, because script/at_home/hand-over
      # uses it to deliver proofs claimed by clients that are no longer running.
      public

      def hand_over(wanted, tally)
        Array(wanted).each do |sha256|
          unless File.exist?(proof_path(sha256))
            report&.call("proof #{sha256[0, 12]} requested but not on this disk")
            tally["proof missing"] += 1
            next
          end

          answer = post_proof(sha256)
          next unless answer

          outcome = if answer[:accepted] then "proof delivered"
                    elsif answer[:discard] then "proof discarded"
                    else "proof refused"
                    end
          tally[outcome] += 1
          report&.call("proof #{sha256[0, 12]}  #{answer[:note]}")

          # The coordinator holds the bytes now, written whole under the same
          # digest, or will never take them: either way this copy is only
          # taking up a volunteer's disk.
          File.delete(proof_path(sha256)) if answer[:accepted] || answer[:discard]
        end
      end

      # Proofs the coordinator has decided it will never take, usually because
      # they were over its cap and their cube was split instead.
      def discard(digests, tally)
        Array(digests).each do |sha256|
          next unless File.exist?(proof_path(sha256))

          File.delete(proof_path(sha256))
          tally["proof discarded"] += 1
          report&.call("proof #{sha256[0, 12]}  discarded, the coordinator will not take it")
        end
      end

      private

      # Retries while the coordinator is unreachable or unwell, and raises
      # only on failures retrying cannot fix (a malformed request of ours).
      # Returns nil if it gives up, so callers can stop cleanly rather than
      # crash with a stack trace in a volunteer's terminal.
      def deliver(path, body, content_type)
        waited = 0
        attempt = 0
        begin
          exchange(path, body, content_type)
        rescue *TRANSIENT_ERRORS, TransientResponse => error
          delay = RETRY_DELAYS[[attempt, RETRY_DELAYS.size - 1].min]
          if give_up_after && waited + delay > give_up_after
            report&.call("coordinator still unreachable after #{waited}s — stopping (#{error.class})")
            return nil
          end

          report&.call("coordinator unavailable (#{error.class}); retrying in #{delay}s")
          sleep(delay)
          waited += delay
          attempt += 1
          retry
        end
      end

      # Retried like everything else, since a formula download is the one part
      # of a lease a volunteer cannot work around by trying again later.
      def fetch(path)
        waited = 0
        attempt = 0
        begin
          get(path)
        rescue *TRANSIENT_ERRORS, TransientResponse => error
          delay = RETRY_DELAYS[[attempt, RETRY_DELAYS.size - 1].min]
          if give_up_after && waited + delay > give_up_after
            report&.call("could not fetch #{path} after #{waited}s (#{error.class})")
            return nil
          end

          sleep(delay)
          waited += delay
          attempt += 1
          retry
        end
      end

      def get(path)
        request = Net::HTTP::Get.new(URI.join(base, path))
        response = Net::HTTP.start(base.host, base.port, read_timeout: 300, open_timeout: 30) { it.request(request) }
        status = response.code.to_i
        raise TransientResponse, "HTTP #{status}" if status == TOO_MANY_REQUESTS || status >= SERVER_ERROR_FLOOR
        return nil unless status == 200

        response.body
      end

      def exchange(path, body, content_type)
        request = Net::HTTP::Post.new(URI.join(base, path))
        request["Content-Type"] = content_type
        request.body = body
        response = Net::HTTP.start(base.host, base.port, read_timeout: 300, open_timeout: 30) { it.request(request) }

        # Throttling and server errors mean "not now"; other 4xx means we
        # asked wrongly and repeating it would just be rude.
        status = response.code.to_i
        raise TransientResponse, "HTTP #{status}" if status == TOO_MANY_REQUESTS || status >= SERVER_ERROR_FLOOR

        JSON.parse(response.body, symbolize_names: true)
      end
    end
  end
end
