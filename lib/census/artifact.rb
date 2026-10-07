# frozen_string_literal: true

require "digest"

module Census
  # A SAT artifact too big for git (a formula or a DRAT proof under some
  # shape's cnf/), as the publish script and the manifest see it: which
  # shape it belongs to, where it lives in the bucket, what it is, and the
  # checksum that lets a stranger confirm they downloaded the right bytes.
  class Artifact
    attr_reader :path, :root

    def initialize(path:, root:)
      @path = path
      @root = root
    end

    # "9/8219/cnf/corona2.drat", as a record's refutation field would say it.
    def relative_path = Pathname(path).relative_path_from(Pathname(root)).to_s

    def id = relative_path.split("/").first(2).join("/")

    def name = File.basename(path)

    def key = "public/#{id}/#{name}.xz"

    def bytes = File.size(path)

    def sha256 = @sha256 ||= Digest::SHA256.file(path).hexdigest

    def description
      depth = name[/corona(\d+)/, 1]
      case File.extname(name)
      when ".drat" then "DRAT refutation of corona-#{depth} of #{id}"
      when ".cnf"  then "formula for corona-#{depth} of #{id}"
      else name
      end
    end
  end
end
