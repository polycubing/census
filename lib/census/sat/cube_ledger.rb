# frozen_string_literal: true

require "json"

module Census
  module SAT
    # The results ledger script/cube-solve appends to beside a cube file: one
    # JSON line per attempt, {cube, verdict, seconds}. A cube can appear more
    # than once, because TIMEOUT and ERROR are retried, so a verdict is read
    # as "ever refuted" or "ever satisfied", never "last line wins".
    class CubeLedger
      def initialize(path:)
        @path = path
      end

      def entries = @entries ||= File.readlines(@path).map { JSON.parse(it, symbolize_names: true) }

      def refuted = ids_with("UNSATISFIABLE")

      def satisfied = ids_with("SATISFIABLE")

      # Cubes with no decisive verdict, given how many cubes the file holds.
      def pending(count:) = (0...count).to_a - refuted - satisfied

      private

      def ids_with(verdict) = entries.select { it[:verdict] == verdict }.map { it[:cube] }.uniq.sort
    end
  end
end
