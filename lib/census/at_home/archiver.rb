# frozen_string_literal: true

module Census
  module AtHome
    # LOCKSS for computed results: move what the coordinator has learned out
    # of Postgres and into plaintext files under data/, where git and (for
    # the big pieces) S3 keep copies. The database is scheduling state — if
    # it dies we lose in-flight leases and nothing else, because the archive
    # is reconstructible without it and it is reconstructible from the
    # archive.
    #
    # Idempotent by comparison rather than bookkeeping: it asks "what does
    # the coordinator know that data/ doesn't?" every run, so a lost flag
    # can never cause a silent gap.
    class Archiver
      def initialize(store:, root:, report: nil)
        @store = store
        @root = root
        @report = report
      end

      # Returns the shape ids written. Verifies every certificate a third
      # time (worker → coordinator → here) before it reaches the archive.
      def archive
        written = []
        store.accepted_shape_results.each do |result|
          path = File.join(root, result[:shape_id], "shape.json")
          record = JSON.parse(File.read(path), symbolize_names: true)
          next if record[:verdict]

          shape = Polycube.new(cells: record[:cells])
          certificate = result[:certificate]
          unless Verifier.new(certificate:, shape:).valid?
            report&.call("REFUSED #{result[:shape_id]}: certificate failed verification at promotion")
            next
          end

          File.write(path, JSONDocument.new(stamped(record, certificate, result)).generate)
          report&.call("#{result[:shape_id]}  tiler  #{certificate[:type]}  (credit: #{result[:credit]})")
          written << result[:shape_id]
        end
        written
      end

      private

      attr_reader :report, :root, :store

      def stamped(record, certificate, result)
        stamped = record.merge(
          verdict: "tiler",
          tiles_rotations_only: true,
          tiles_with_reflections: true,
          certificate:,
          budgets: result[:budgets] || record[:budgets],
          credits: record[:credits].merge(solved_by: "polycube-census v#{VERSION} (@home: #{result[:credit]})")
        )
        Stages.stamp(stamped)
      end
    end
  end
end
