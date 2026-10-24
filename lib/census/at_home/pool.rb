# frozen_string_literal: true

require "pg"

module Census
  module AtHome
    # A minimal connection pool. Puma is genuinely concurrent, so the single
    # mutex-guarded connection that served the WEBrick spike would serialize
    # the whole coordinator; this hands each request its own connection and
    # blocks only when every one is busy.
    #
    # A connection the server has dropped is discarded and the work retried
    # once on a fresh one. Postgres on the colo crashed and recovered in
    # twenty seconds on 2026-10-17, and the hub then answered every request
    # for a week with the dead sockets it still held.
    class Pool
      DROPPED = [PG::ConnectionBad, PG::UnableToSend].freeze

      def initialize(url:, size: 8, timeout: 5)
        @url = url
        @size = size
        @timeout = timeout
        @available = Queue.new
        @created = 0
        @mutex = Mutex.new
      end

      def with
        tries = 0
        begin
          connection = checkout
          broken = false
          begin
            yield connection
          rescue *DROPPED
            broken = true
            raise
          ensure
            broken ? discard(connection) : @available << connection
          end
        rescue *DROPPED
          retry if (tries += 1) <= 1
          raise
        end
      end

      def close
        @available.close
        @available.size.times { @available.pop&.close }
      end

      private

      def checkout
        mutex.synchronize do
          if @created < size
            @created += 1
            return PG.connect(url)
          end
        end
        Timeout.timeout(timeout) { @available.pop }
      end

      def discard(connection)
        begin
          connection.close
        rescue StandardError
          nil
        end
        mutex.synchronize { @created -= 1 }
      end

      attr_reader :mutex, :size, :timeout, :url
    end
  end
end
