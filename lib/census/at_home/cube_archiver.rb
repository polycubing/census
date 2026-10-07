# frozen_string_literal: true

require "date"
require "digest"
require "fileutils"

module Census
  module AtHome
    # Turns a finished cube campaign into a record's claim. The coordinator
    # knows every leaf cube, its proof's digest, and that drat-trim checked
    # the proof on delivery. This writes that knowledge as a manifest beside
    # the record (one line per leaf), hashes the manifest, and stamps the
    # record with `refutation_kind: cube_proofs` and that hash. A mirror twin
    # that derives its verdict from this shape is restamped to match.
    #
    # Refuses to write unless the shape unit is `done`, which the roll-up
    # grants only when every leaf's proof was checked. A campaign with one
    # cube still open is not a refutation and must not be dressed up as one.
    class CubeArchiver
      class NotClosed < StandardError; end

      def initialize(store:, root:, shape_id:, depth:, checker:, solver:)
        @store = store
        @root = root
        @shape_id = shape_id
        @depth = depth
        @checker = checker
        @solver = solver
      end

      def archive
        shape = store.shape_unit(shape_id)
        raise NotClosed, "#{shape_id} has no shape unit" unless shape
        raise NotClosed, "#{shape_id}'s shape unit is #{shape[:status]}, not done" unless shape[:status] == "done"

        leaves = store.cube_leaves(shape_id:)
        unchecked = leaves.reject { it[:proof_state] == "verified" }
        raise NotClosed, "#{unchecked.size} of #{leaves.size} leaf proofs are not verified" unless unchecked.empty?

        FileUtils.mkdir_p(File.dirname(manifest_path))
        File.write(manifest_path, JSONDocument.new(manifest(leaves)).generate)
        sha256 = Digest::SHA256.file(manifest_path).hexdigest
        stamp(record_path(shape_id), sha256:, count: leaves.size)
        twin = stamp_twin(sha256:, count: leaves.size)

        { leaves: leaves.size, manifest: manifest_path, sha256:, twin: }
      end

      def manifest_name = "corona#{depth}.proofs.json"

      def manifest_path = File.join(root, shape_id, "cnf", manifest_name)

      private

      attr_reader :checker, :depth, :root, :shape_id, :solver, :store

      def record_path(id) = File.join(root, id, "shape.json")

      def read(path) = JSON.parse(File.read(path), symbolize_names: true)

      def manifest(leaves)
        {
          shape_id:,
          corona_depth: depth,
          formula_sha256: leaves.first[:cnf_sha256],
          checker:,
          solver:,
          proofs: leaves.size,
          leaves: leaves.map do |leaf|
            { cube: leaf[:cube], proof: { bytes: leaf[:proof_bytes], sha256: leaf[:proof_sha256] }, solve_seconds: leaf[:seconds] }
          end
        }
      end

      def solved_with(count)
        "cube-and-conquer through polycubing@home: #{count} cube refutations by #{solver}, " \
          "each DRAT proof checked by #{checker} on delivery; cover audited by script/audit-cubes"
      end

      def stamp(path, sha256:, count:)
        record = read(path)
        previous = record.dig(:certificate, :solved_with)
        certificate = (record[:certificate] || {}).merge(
          type: "heesch",
          heesch: depth - 1,
          adjacency: "26",
          derived_from: nil,
          provenance: "computed",
          refutation: "cnf/#{manifest_name}",
          refutation_kind: "cube_proofs",
          refutation_sha256: sha256,
          solved_with: previous ? "#{solved_with(count)}; replaces: #{previous}" : solved_with(count),
          checked: { checker:, date: Date.today.iso8601, proofs: count, verdict: "VERIFIED" }
        )
        stamped = record.merge(
          verdict: "non_tiler",
          tiles_rotations_only: false,
          tiles_with_reflections: false,
          certificate:,
          heesch: depth - 1,
          budgets: (record[:budgets] || {}).merge(corona_depth: depth),
          reached: (record[:reached] || {}).merge(corona_refuted: depth),
          credits: record[:credits].merge(solved_by: "polycube-census v#{VERSION} (@home)")
        )
        File.write(path, JSONDocument.new(Stages.stamp(stamped)).generate)
      end

      # A twin whose refutation points here carries the new kind and digest,
      # so script/verify's derived check still finds them equal.
      def stamp_twin(sha256:, count:)
        record = read(record_path(shape_id))
        twin_id = record[:mirror_id]
        return nil if twin_id == shape_id

        twin = read(record_path(twin_id))
        return nil unless twin.dig(:certificate, :derived_from) == shape_id

        certificate = twin[:certificate].merge(
          refutation: "mirror of #{shape_id} — data/#{shape_id}/cnf/#{manifest_name}",
          refutation_kind: "cube_proofs",
          refutation_sha256: sha256,
          solved_with: "witness and verdict mirrored from #{shape_id}; #{solved_with(count)}"
        )
        File.write(record_path(twin_id), JSONDocument.new(Stages.stamp(twin.merge(certificate:))).generate)
        twin_id
      end
    end
  end
end
