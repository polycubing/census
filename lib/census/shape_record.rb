# frozen_string_literal: true

require "json"

module Census
  # The shape.json document for one census entry. Geometry fields are filled
  # at enumeration time; verdict fields stay null until the pipeline runs.
  class ShapeRecord
    attr_reader :shape, :index, :mirror_index

    def initialize(shape:, index:, mirror_index:)
      @shape = shape
      @index = index
      @mirror_index = mirror_index
    end

    def id = "#{shape.size}/#{index}"

    def mirror_id = "#{shape.size}/#{mirror_index}"

    def to_h = geometry_fields.merge(verdict_fields)

    def to_json_document = JSONDocument.new(to_h).generate

    private

    def geometry_fields
      {
        id:,
        n: shape.size,
        cells: shape.cells,
        symmetry_order: shape.symmetry_order,
        chiral: shape.chiral?,
        mirror_id:
      }
    end

    def verdict_fields
      {
        verdict: nil,
        tiles_rotations_only: nil,
        tiles_with_reflections: nil,
        certificate: nil,
        heesch: nil,
        budgets: {},
        credits: { solved_by: nil, verified_by: nil, prior_art: nil },
        stages: []
      }
    end
  end
end
