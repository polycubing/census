# frozen_string_literal: true

RSpec.describe Census::AtHome::CubeArchiver, :home do
  let(:store) { Census::AtHome::Store.new }
  let(:coordinator) { Census::AtHome::Coordinator.new(store:, proof_policy: :every) }
  let(:fixtures) { File.expand_path("../../fixtures", __dir__) }
  let(:cnf_path) { File.join(fixtures, "proof", "contradiction.cnf") }

  around do |example|
    Dir.mktmpdir do |dir|
      @root = dir
      FileUtils.mkdir_p(File.join(dir, "3/2"))
      FileUtils.cp(File.join(fixtures, "3/2/shape.json"), File.join(dir, "3/2/shape.json"))
      example.run
    end
  end

  before { store.reset }
  after { store.close }

  def tree
    levels = %w[base.icnf clause-split.icnf].map { Census::SAT::CubeTree.level(File.join(fixtures, "cubes", it)) }
    Census::SAT::CubeTree.new(levels:)
  end

  def seed
    Census::AtHome::CubeSeeder.new(store:, tree:, shape_id: "3/2", cells: [[0, 0, 0], [0, 0, 1], [0, 1, 0]], budgets: {}, cnf_path:).seed
  end

  # Refute every leaf the way the campaign does, proof claimed then checked.
  def refute_all
    worker = coordinator.register(handle: "spec")
    store.cube_leaves(shape_id: "3/2").each do |leaf|
      digest = Digest::SHA256.hexdigest(leaf[:cube].inspect)
      coordinator.submit(unit_id: leaf[:id], client_id: worker[:id], verdict: "unsat",
                         payload: { cube: leaf[:cube], proof: { sha256: digest, bytes: 8 } }, seconds: 0.5)
      store.record_proof(id: store.wanted_proof(digest)[:id], state: "verified", path: "/proofs/#{digest}.drat")
    end
    coordinator.settle(shape_id: "3/2")
  end

  def archiver
    described_class.new(store:, root: @root, shape_id: "3/2", depth: 2, checker: "drat-trim 2e3b2dc", solver: "kissat 4.0.4")
  end

  it "refuses a shape whose tree has not closed" do
    seed
    expect { archiver.archive }.to raise_error(described_class::NotClosed, /split, not done/)
    expect(File.exist?(archiver.manifest_path)).to be(false)
  end

  it "writes one manifest line per leaf, with each proof's digest" do
    seed
    refute_all
    result = archiver.archive

    manifest = JSON.parse(File.read(result[:manifest]), symbolize_names: true)
    expect(result[:leaves]).to eq(6)
    expect(manifest[:proofs]).to eq(6)
    expect(manifest[:leaves].map { it[:cube] }).to include([1, 2], [-1, -2, -5, -7])
    expect(manifest[:leaves]).to all(include(proof: { bytes: 8, sha256: a_string_matching(/\A[0-9a-f]{64}\z/) }))
    expect(manifest[:formula_sha256]).to eq(Digest::SHA256.file(cnf_path).hexdigest)
  end

  it "stamps the record as a non-tiler backed by cube proofs, naming the manifest's digest" do
    seed
    refute_all
    result = archiver.archive

    record = JSON.parse(File.read(File.join(@root, "3/2/shape.json")), symbolize_names: true)
    expect(record[:verdict]).to eq("non_tiler")
    expect(record[:heesch]).to eq(1)
    expect(record[:certificate]).to include(refutation_kind: "cube_proofs", refutation: "cnf/corona2.proofs.json",
                                            refutation_sha256: result[:sha256], provenance: "computed")
    expect(record[:certificate][:checked]).to include(proofs: 6, verdict: "VERIFIED", checker: "drat-trim 2e3b2dc")
    expect(record[:reached]).to eq({ corona_refuted: 2 })
    expect(record[:stages].last).to eq({ stage: "corona", outcome: "refuted", depth: 2 })
  end

  it "hashes the manifest it wrote" do
    seed
    refute_all
    result = archiver.archive

    expect(Digest::SHA256.file(result[:manifest]).hexdigest).to eq(result[:sha256])
  end
end
