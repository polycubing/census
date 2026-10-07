# frozen_string_literal: true

module Census
  module SAT
    # The cover tree of a cube-and-conquer campaign: cube files for each
    # level, each with its ledger. A cube is refuted (its ledger says so),
    # standing (no refutation, so the next level must partition it), or
    # beside the point (its parent was refuted anyway). The tree is closed
    # when every standing cube is partitioned by its children and the last
    # level leaves nothing standing. The refuted cubes reachable from the
    # root through standing parents are the leaves: exactly the proofs a
    # refutation of the whole formula rests on.
    class CubeTree
      Node = Struct.new(:cube, :level, :parent, :refuted, :children) do
        def standing? = !refuted
      end

      # One level from a cube file, with its ledger beside it.
      def self.level(path)
        { cubes: CubeFile.new(path:).cubes, ledger: CubeLedger.new(path: "#{path}.results.jsonl"), path: }
      end

      def initialize(levels:)
        @levels = levels
      end

      def closed? = failures.empty?

      def failures
        @failures ||= build && @problems
      end

      def leaves = nodes.select(&:refuted)

      def split_nodes = nodes.select { it.standing? && !it.children.empty? }

      def nodes
        build
        @nodes
      end

      private

      attr_reader :levels

      def build
        return true if @nodes

        @problems = []
        @nodes = []
        standing = []

        levels.each_with_index do |level, position|
          cubes, ledger, path = level.values_at(:cubes, :ledger, :path)
          name = File.basename(path.to_s)
          @problems << "#{name}: SATISFIABLE cube(s) #{ledger.satisfied.inspect}" unless ledger.satisfied.empty?

          refuted = ledger.refuted.to_set
          cover = CubeCover.new(cubes:)
          current = cubes.each_with_index.map { |cube, index| Node.new(cube, position, nil, refuted.include?(index), []) }

          if position.zero?
            @problems << "#{name}: not a complete sign cover of the formula" unless cover.complete?
            relevant = current
          else
            unpartitioned = standing.reject { cover.partitions?(it.cube) }
            @problems << "#{name}: #{unpartitioned.size} standing cube(s) from the previous level not partitioned" unless unpartitioned.empty?
            relevant = current.select do |node|
              parent = standing.find { (it.cube - node.cube).empty? }
              next false unless parent

              node.parent = parent
              parent.children << node
              true
            end
          end

          @nodes.concat(relevant)
          standing = relevant.select(&:standing?)
        end

        @problems << "#{File.basename(levels.last[:path].to_s)}: #{standing.size} cube(s) still standing" unless standing.empty?
        true
      end
    end
  end
end
