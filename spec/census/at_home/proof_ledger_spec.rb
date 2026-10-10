# frozen_string_literal: true

RSpec.describe Census::AtHome::ProofLedger do
  around { |example| Dir.mktmpdir { |dir| @root = dir and example.run } }

  let(:path) { described_class.path(root: @root, shape_id: "9/42947", depth: 2) }
  let(:ledger) { described_class.new(path:, shape_id: "9/42947", depth: 2) }
  let(:digest) { "a" * 64 }

  it "names the ledger beside the record and the object under the shape's proofs prefix" do
    expect(path).to eq(File.join(@root, "9/42947/cnf/corona2.published.json"))
    expect(ledger.key(digest)).to eq("public/9/42947/proofs/#{digest}.drat.xz")
    expect(ledger.url(digest)).to start_with("https://polycubes.s3.us-west-2.amazonaws.com/public/9/42947/proofs/")
  end

  it "records a published proof and reads it back from disk" do
    ledger.add(sha256: digest, bytes: 100, compressed_bytes: 10, compressed_sha256: "b" * 64, published: Date.new(2026, 10, 9))

    reread = described_class.new(path:, shape_id: "9/42947", depth: 2)
    expect(reread.include?(digest)).to be(true)
    expect(reread[digest]).to eq(bytes: 100, compressed: { bytes: 10, sha256: "b" * 64 }, published: "2026-10-09",
                                 url: ledger.url(digest))
    expect(reread.size).to eq(1)
  end

  it "keeps digests sorted so the file diffs cleanly" do
    ledger.add(sha256: "c" * 64, bytes: 1, compressed_bytes: 1, compressed_sha256: "d" * 64)
    ledger.add(sha256: "a" * 64, bytes: 1, compressed_bytes: 1, compressed_sha256: "d" * 64)

    expect(JSON.parse(File.read(path))["proofs"].keys).to eq(["a" * 64, "c" * 64])
  end
end
