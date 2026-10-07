# frozen_string_literal: true

RSpec.describe Census::Stages do
  def stages_for(fields)
    described_class.new(record: fields).to_a
  end

  it "is empty for an unresolved shape" do
    expect(stages_for(verdict: nil, certificate: nil, budgets: {})).to eq([])
  end

  it "records a box tiler as one certified stage with the box volume" do
    record = { verdict: "tiler", certificate: { type: "box", box: [2, 2, 2] }, budgets: { box_max_volume: 96, torus_max_index: 48 } }
    expect(stages_for(record)).to eq([{ stage: "box", outcome: "certified", volume: 8 }])
  end

  it "records a torus tiler as box exhausted then torus certified at the lattice index" do
    record = {
      verdict: "tiler",
      certificate: { type: "torus", lattice: [[3, 0, 0], [1, 2, 0], [0, 0, 9]] },
      budgets: { box_max_volume: 128, torus_max_index: 72 }
    }
    expect(stages_for(record)).to eq([
      { stage: "box", outcome: "exhausted", volume: 128 },
      { stage: "torus", outcome: "certified", index: 54 }
    ])
  end

  it "records an open shape as every stage exhausted, witnessed, or attempted" do
    record = {
      verdict: "open",
      certificate: nil,
      budgets: { box_max_volume: 128, corona_depth: 3, torus_max_index: 72 },
      reached: { corona_sat: 2 },
      attempts: [{ depth: 3, status: "running" }]
    }
    expect(stages_for(record)).to eq([
      { stage: "box", outcome: "exhausted", volume: 128 },
      { stage: "torus", outcome: "exhausted", index: 72 },
      { stage: "corona", outcome: "witnessed", depth: 2 },
      { stage: "corona", outcome: "attempted", depth: 3 }
    ])
  end

  it "records a non-tiler as witnessed at its Heesch number and refuted one deeper" do
    record = {
      verdict: "non_tiler",
      certificate: { type: "heesch", heesch: 1 },
      heesch: 1,
      budgets: { box_max_volume: 96, corona_depth: 2, torus_max_index: 72 },
      reached: { corona_refuted: 2 }
    }
    expect(stages_for(record)).to eq([
      { stage: "box", outcome: "exhausted", volume: 96 },
      { stage: "torus", outcome: "exhausted", index: 72 },
      { stage: "corona", outcome: "witnessed", depth: 1 },
      { stage: "corona", outcome: "refuted", depth: 2 }
    ])
  end

  it "leaves out a stage whose budget was never set" do
    record = { verdict: "tiler", certificate: { type: "torus", lattice: [[1, 0, 0], [0, 1, 0], [0, 0, 2]] }, budgets: { torus_max_index: 48 } }
    expect(stages_for(record)).to eq([{ stage: "torus", outcome: "certified", index: 2 }])
  end
end
