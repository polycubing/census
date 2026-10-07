# frozen_string_literal: true

RSpec.describe Census::AtHome::CubeSeeder, :home do
  let(:store) { Census::AtHome::Store.new }
  let(:fixtures) { File.expand_path("../../fixtures", __dir__) }
  let(:cnf_path) { File.join(fixtures, "proof", "contradiction.cnf") }

  def tree(*names)
    levels = names.map { Census::SAT::CubeTree.level(File.join(fixtures, "cubes", it)) }
    Census::SAT::CubeTree.new(levels:)
  end

  def seeder(tree)
    described_class.new(store:, tree:, shape_id: "3/2", cells: [[0, 0, 0], [0, 0, 1], [0, 1, 0]], budgets: {}, cnf_path:)
  end

  before { store.reset }
  after { store.close }

  it "queues one pending unit per leaf and marks the shape and standing cubes split" do
    expect(seeder(tree("base.icnf", "clause-split.icnf")).seed).to eq({ leaves: 6, splits: 2 })
    expect(store.status[:units]).to eq({ "pending" => 6, "split" => 2 })
  end

  it "hands out leaves that carry the formula's digest and their cube" do
    seeder(tree("base.icnf", "clause-split.icnf")).seed
    client = store.register_client(handle: "seed-spec")
    unit = store.lease_unit(client_id: client[:id], seconds: 60)
    expect(unit[:kind]).to eq("cube")
    expect(unit[:payload]).to include(cnf_path:, cnf_sha256: Digest::SHA256.file(cnf_path).hexdigest)
    expect(unit[:payload][:cube]).to eq([1, 2])
  end

  it "nests a split cube's children under it" do
    seeder(tree("base.icnf", "clause-split.icnf")).seed
    split = store.unit(5)
    child = store.unit(6)
    expect(split[:status]).to eq("split")
    expect(split[:payload][:cube]).to eq([-1, -2])
    expect(child[:parent_id]).to eq(5)
    expect(child[:payload][:cube]).to eq([-1, -2, 5])
  end

  it "refuses a cover that is not closed" do
    expect { seeder(tree("base.icnf")).seed }.to raise_error(ArgumentError, /not closed/)
    expect(store.status[:units]).to eq({})
  end

  it "refuses to seed a shape twice" do
    seeder(tree("base.icnf", "clause-split.icnf")).seed
    expect { seeder(tree("base.icnf", "clause-split.icnf")).seed }.to raise_error(described_class::AlreadySeeded)
  end
end
