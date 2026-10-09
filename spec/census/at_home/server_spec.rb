# frozen_string_literal: true

require "rack/test"

RSpec.describe Census::AtHome::Server, :home do
  include Rack::Test::Methods

  let(:store) { Census::AtHome::Store.new }
  let(:straight) { Census::Polycube.new(cells: [[0, 0, 0], [0, 0, 1], [0, 0, 2]]) }

  def app = described_class

  before do
    store.load_schema(File.expand_path("../../../db/at_home.sql", __dir__))
    store.reset
    described_class.coordinator = Census::AtHome::Coordinator.new(store:)
  end

  after { store.close }

  def post_json(path, body)
    post(path, JSON.generate(body), "CONTENT_TYPE" => "application/json")
    JSON.parse(last_response.body, symbolize_names: true)
  end

  it "reports status as JSON" do
    get "/status"
    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)).to include("units", "results", "clients")
  end

  it "registers a client and hands out its id" do
    body = post_json("/register", { handle: "spec-client" })
    expect(body.dig(:client, :handle)).to eq("spec-client")
  end

  it "logs the exception behind a 400 so a crash is never silent" do
    logged = nil
    allow_any_instance_of(described_class).to receive(:warn) { |_instance, message| logged = message }

    post_json("/register", {})
    expect(logged).to include("ERROR", "/register", "missing handle")
  end

  it "refuses a request missing a required field" do
    body = post_json("/register", {})
    expect(last_response.status).to eq(400)
    expect(body[:error]).to match(/missing handle/)
  end

  it "refuses a body that is not a JSON object" do
    post("/register", JSON.generate([1, 2, 3]), "CONTENT_TYPE" => "application/json")
    expect(last_response.status).to eq(400)
  end

  it "refuses a body larger than the cap before parsing it" do
    oversized = JSON.generate({ handle: "x", contact: "A" * (described_class::MAX_BODY_BYTES + 1) })
    post("/register", oversized, "CONTENT_TYPE" => "application/json")
    expect(last_response.status).to eq(413)
  end

  it "leases a seeded unit and accepts a verified certificate over HTTP" do
    store.add_unit(kind: "shape", shape_id: "3/1", payload: { cells: straight.cells, budgets: {} })
    client_id = post_json("/register", { handle: "spec-client" }).dig(:client, :id)

    unit = post_json("/lease", { client_id: })[:unit]
    expect(unit).to include(shape_id: "3/1")

    certificate = Census::TorusSearch.new(shape: straight).certificate
    answer = post_json("/results", { unit_id: unit[:id], client_id:, verdict: "tiler", payload: { certificate: } })
    expect(answer[:accepted]).to be(true)
  end

  it "rejects a forged certificate over HTTP without crashing" do
    store.add_unit(kind: "shape", shape_id: "3/1", payload: { cells: straight.cells, budgets: {} })
    client_id = post_json("/register", { handle: "liar" }).dig(:client, :id)
    unit = post_json("/lease", { client_id: })[:unit]

    forged = { type: "torus", lattice: [[1, 0, 0], [0, 1, 0], [0, 0, 1]],
               placements: [{ rotation: 0, offset: [0, 0, 0] }] }
    answer = post_json("/results", { unit_id: unit[:id], client_id:, verdict: "tiler", payload: { certificate: forged } })
    expect(answer[:accepted]).to be(false)
  end
end

RSpec.describe Census::AtHome::Server, "proofs over the cap", :home do
  include Rack::Test::Methods

  let(:store) { Census::AtHome::Store.new }
  let(:digest) { "d" * 64 }

  def app = described_class

  before do
    store.load_schema(File.expand_path("../../../db/at_home.sql", __dir__))
    store.reset
    described_class.coordinator = Census::AtHome::Coordinator.new(store:, proof_policy: :every, max_proof_bytes: 4)
  end

  after { store.close }

  def post_json(path, body)
    post(path, JSON.generate(body), "CONTENT_TYPE" => "application/json")
    JSON.parse(last_response.body, symbolize_names: true)
  end

  it "answers an upload over the cap with a split and a discard, not an error" do
    store.add_unit(kind: "cube", shape_id: "8/1309", payload: { cnf_path: "spec/fixtures/proof/contradiction.cnf", cube: [1] })
    worker = post_json("/register", { handle: "spec" })[:client]
    unit = post_json("/lease", { client_id: worker[:id] })[:unit]
    # A claim that understates its size, so the upload itself is what trips the cap.
    post_json("/results", { unit_id: unit[:id], client_id: worker[:id], verdict: "unsat",
                            payload: { cube: [1], proof: { sha256: digest, bytes: 2 } } })

    post "/proof/#{digest}", "12345678", "CONTENT_TYPE" => "application/octet-stream"

    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body, symbolize_names: true)).to include(accepted: false, discard: true, note: /4 byte cap/)
    expect(post_json("/lease", { client_id: worker[:id] })).to include(wanted_proofs: [], discard_proofs: [digest])
  end
end
