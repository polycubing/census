# frozen_string_literal: true

require "digest"

module Census
  module AtHome
    # Lays a campaign's cover tree into the coordinator's queue so volunteers
    # re-solve exactly the cubes a refutation rests on, this time writing
    # proofs. The shape unit and every standing cube go in as `split`, since
    # their evidence is their children's. Every refuted cube goes in pending,
    # one unit each, and the coordinator's roll-up closes the parents as the
    # proofs come back. Nothing is seeded unless the tree is closed: a cover
    # with a gap is not a refutation and must not be dressed up as one.
    class CubeSeeder
      class AlreadySeeded < StandardError; end

      #
      # open: an open campaign rather than a re-proof. The tree's first level
      # is a partition of the search space whose cubes have not been settled,
      # and every one of them goes in pending, ledgers ignored. The hub
      # splits the hard ones as they exhaust. The shape closes only if every
      # cube is refuted with a proof; a satisfying cube is a witness.
      def initialize(store:, tree:, shape_id:, cells:, budgets:, cnf_path:, open: false)
        @store = store
        @tree = tree
        @shape_id = shape_id
        @cells = cells
        @budgets = budgets
        @cnf_path = cnf_path
        @open = open
      end

      def seed
        return seed_open if @open

        raise ArgumentError, "cover is not closed: #{tree.failures.join('. ')}" unless tree.closed?

        shape_unit = store.add_unit(kind: "shape", shape_id:, payload: { cells:, budgets: })
        raise AlreadySeeded, "#{shape_id} already has a shape unit" unless shape_unit

        store.close_unit(id: shape_unit, status: "split")
        @leaves = 0
        @splits = 1
        tree.nodes.select { it.level.zero? }.each { place(it, shape_unit) }
        { leaves: @leaves, splits: @splits }
      end

      private

      attr_reader :budgets, :cells, :cnf_path, :shape_id, :store, :tree

      def seed_open
        shape_unit = store.add_unit(kind: "shape", shape_id:, payload: { cells:, budgets: })
        raise AlreadySeeded, "#{shape_id} already has a shape unit" unless shape_unit

        store.close_unit(id: shape_unit, status: "split")
        cubes = tree.levels.first.fetch(:cubes)
        cubes.each { store.add_unit(kind: "cube", shape_id:, parent_id: shape_unit, payload: { cnf_path:, cnf_sha256:, cube: it }) }
        { leaves: cubes.size, splits: 1 }
      end

      def cnf_sha256 = @cnf_sha256 ||= Digest::SHA256.file(cnf_path).hexdigest

      def place(node, parent_id)
        id = store.add_unit(kind: "cube", shape_id:, parent_id:, payload: { cnf_path:, cnf_sha256:, cube: node.cube })
        if node.refuted
          @leaves += 1
          return
        end

        store.close_unit(id:, status: "split")
        @splits += 1
        node.children.each { place(it, id) }
      end
    end
  end
end
