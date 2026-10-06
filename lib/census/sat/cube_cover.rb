# frozen_string_literal: true

module Census
  module SAT
    # Whether a set of cubes covers what it claims to. Cube-and-conquer is
    # sound only if the cubes jointly cover every assignment: a cube missing
    # from the cover is a region nobody refuted. Two kinds of cover appear in
    # the census. A sign cover is every sign pattern over one set of variables
    # (script/make-cubes, script/subsplit-cubes). A first-true split branches
    # on a clause q1..qn: q1, then not-q1 q2, and so on, then every q negated
    # (script/clause-split-cubes). Both partition the region they split.
    class CubeCover
      def initialize(cubes:)
        @cubes = cubes
      end

      def complete? = sign_cover?(cubes)

      def children_of(parent) = cubes.select { (parent - it).empty? }

      # The cubes extending parent split its region with nothing left over.
      def partitions?(parent)
        tails = children_of(parent).map { it - parent }
        return false if tails.empty?

        sign_cover?(tails) || first_true_split?(tails)
      end

      private

      attr_reader :cubes

      def sign_cover?(tails)
        variables = tails.map { |tail| tail.map(&:abs).sort }.uniq
        return false unless variables.size == 1 && variables.first.uniq.size == variables.first.size

        tails.map(&:sort).uniq.size == 2**variables.first.size
      end

      def first_true_split?(tails)
        negated = tails.find { it.none?(&:positive?) }
        return false unless negated

        sequence = negated.map(&:abs)
        branches = sequence.each_index.map { sequence.first(it).map(&:-@) + [sequence[it]] }
        tails.sort == (branches << negated).sort
      end
    end
  end
end
