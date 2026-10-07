# frozen_string_literal: true

module Census
  # Runs the certificate stages over every unresolved shape.json under root,
  # verifying and stamping verdicts as it goes. Yields one line per solved shape.
  class Pipeline
    def initialize(root:,
                   max_index: TorusSearch::DEFAULT_MAX_INDEX,
                   max_volume: BoxSearch::DEFAULT_MAX_VOLUME,
                   min_index: 0,
                   min_volume: 0,
                   stop_path: nil)
      @root = Pathname(root)
      @max_index = max_index
      @max_volume = max_volume
      @min_index = min_index
      @min_volume = min_volume
      @stop_path = stop_path || @root.join("..", "STOP")
    end

    # A graceful shutdown between shapes: touch the stop file and every worker
    # finishes its current shape, keeps its stamps, and returns.
    def run(max_size:, shard_count: 1, shard_index: 1, &report)
      (1..max_size).each do |size|
        record_paths(size, shard_count:, shard_index:).each do |path|
          return if stop_requested?

          process(path, &report)
        end
      end
    end

    # Explicit work-list mode: process exactly these ids (e.g. "9/2650"),
    # skipping discovery. The dealt-not-discovered half of a work queue.
    def run_ids(ids, &report)
      ids.each do |id|
        return if stop_requested?

        process(root.join(id, "shape.json").to_s, &report)
      end
    end

    def stop_requested? = File.exist?(stop_path)

    private

    attr_reader :max_index, :max_volume, :min_index, :min_volume, :root, :stop_path

    def record_paths(size, shard_count:, shard_index:)
      Dir.glob(root.join(size.to_s, "*", "shape.json").to_s)
         .sort_by { Integer(File.basename(File.dirname(it))) }
         .select { Integer(File.basename(File.dirname(it))) % shard_count == shard_index % shard_count }
    end

    def process(path, &report)
      record = JSON.parse(File.read(path), symbolize_names: true)
      return if record[:verdict]

      report&.call("#{record[:id]}  solving")
      shape = Polycube.new(cells: record[:cells])
      certificate = BoxSearch.new(shape:, max_volume:, min_volume:).certificate ||
                    TorusSearch.new(shape:, max_index:, min_index:).certificate
      return unless certificate

      stamp(path, record, shape, certificate)
      report&.call("#{record[:id]}  tiler  #{describe(certificate)}")
    end

    def describe(certificate)
      case certificate[:type]
      when "box"   then "box #{certificate[:box].join('x')}"
      when "torus" then "torus index #{Lattice.new(basis: certificate[:lattice]).index}"
      end
    end

    def stamp(path, record, shape, certificate)
      raise "certificate failed verification for #{record[:id]}" unless Verifier.new(certificate:, shape:).valid?

      File.write(path, JSONDocument.new(Stages.stamp(tiler_fields(record, certificate))).generate)
    end

    def tiler_fields(record, certificate)
      record.merge(
        verdict: "tiler",
        tiles_rotations_only: true,
        tiles_with_reflections: true,
        certificate:,
        budgets: { box_max_volume: max_volume, torus_max_index: max_index },
        credits: record[:credits].merge(solved_by: "polycube-census v#{VERSION}")
      )
    end
  end
end
