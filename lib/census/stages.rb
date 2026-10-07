# frozen_string_literal: true

module Census
  # Where a shape has been through the pipeline and how each stage ended,
  # derived from the fields a record already carries. A shape that stalled in
  # the torus stage and one that stalled in corona are different discoveries
  # (the first is a translational-einstein candidate) and used to serialize
  # identically. Stored on the record as `stages` and asserted by script/verify.
  #
  # Outcomes: certified (a tiling certificate was found), exhausted (searched
  # to the limit, nothing), witnessed (a corona of that depth exists),
  # refuted (no corona of that depth exists, so the shape never tiles),
  # attempted (that depth was tried and nothing was settled).
  class Stages
    # The record with its stages filled in from its other fields. Every
    # writer calls this last, so the array can never disagree with them.
    def self.stamp(record) = record.merge(stages: new(record:).to_a)

    def initialize(record:)
      @record = record
    end

    def to_a
      return [] if record[:verdict].nil?

      box_stages + torus_stages + corona_stages
    end

    private

    attr_reader :record

    def certificate = record[:certificate] || {}

    def budgets = record[:budgets] || {}

    def reached = record[:reached] || {}

    def box_stages
      return [{ stage: "box", outcome: "certified", volume: certificate[:box].reduce(:*) }] if certificate[:type] == "box"
      return [] if budgets[:box_max_volume].nil?

      [{ stage: "box", outcome: "exhausted", volume: budgets[:box_max_volume] }]
    end

    def torus_stages
      return [] if certificate[:type] == "box"
      return [{ stage: "torus", outcome: "certified", index: Lattice.new(basis: certificate[:lattice]).index }] if certificate[:type] == "torus"
      return [] if budgets[:torus_max_index].nil?

      [{ stage: "torus", outcome: "exhausted", index: budgets[:torus_max_index] }]
    end

    def corona_stages
      return [] if record[:verdict] == "tiler"

      witnessed = record[:verdict] == "non_tiler" ? record[:heesch] : reached[:corona_sat]
      stages = []
      stages << { stage: "corona", outcome: "witnessed", depth: witnessed } if witnessed&.positive?
      stages << { stage: "corona", outcome: "refuted", depth: reached[:corona_refuted] } if reached[:corona_refuted]
      (record[:attempts] || []).each { stages << { stage: "corona", outcome: "attempted", depth: it[:depth] } }
      stages
    end
  end
end
