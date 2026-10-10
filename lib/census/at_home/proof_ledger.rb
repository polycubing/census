# frozen_string_literal: true

require "date"

module Census
  module AtHome
    # The proofs of one cube campaign that are in the bucket, keyed by
    # digest: the raw size, the compressed object's size and digest, its
    # URL, and the day it went up. Lives beside the record in git, as
    # data/<id>/cnf/corona<K>.published.json, and is the truth about what
    # was published; the bucket is storage. The laptop that drains proofs
    # from the hub publishes them from this ledger and keeps nothing.
    class ProofLedger
      BUCKET = "polycubes"
      REGION = "us-west-2"

      def self.path(root:, shape_id:, depth:) = File.join(root, shape_id, "cnf", "corona#{depth}.published.json")

      attr_reader :path, :shape_id, :depth

      def initialize(path:, shape_id:, depth:)
        @path = path
        @shape_id = shape_id
        @depth = depth
        @proofs = File.exist?(path) ? JSON.parse(File.read(path), symbolize_names: true).fetch(:proofs, {}) : {}
      end

      def key(sha256) = "public/#{shape_id}/proofs/#{sha256}.drat.xz"

      def url(sha256) = "https://#{BUCKET}.s3.#{REGION}.amazonaws.com/#{key(sha256)}"

      def include?(sha256) = @proofs.key?(sha256.to_sym)

      def [](sha256) = @proofs[sha256.to_sym]

      def size = @proofs.size

      def digests = @proofs.keys.map(&:to_s)

      def add(sha256:, bytes:, compressed_bytes:, compressed_sha256:, published: Date.today)
        @proofs[sha256.to_sym] = { bytes:, compressed: { bytes: compressed_bytes, sha256: compressed_sha256 },
                                   published: published.iso8601, url: url(sha256) }
        save
      end

      private

      def save
        document = { bucket: BUCKET, region: REGION, shape_id:, corona_depth: depth, proofs: @proofs.sort.to_h }
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSONDocument.new(document).generate)
      end
    end
  end
end
