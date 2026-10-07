# frozen_string_literal: true

RSpec.describe Census::AtHome::Client do
  # A port nothing is listening on: the coordinator having died, from the
  # client's point of view.
  let(:dead_url) { "http://127.0.0.1:9" }

  it "retries a dead coordinator instead of crashing, then stops cleanly" do
    notes = []
    client = described_class.new(url: dead_url, handle: "spec", give_up_after: 2,
                                 report: ->(line) { notes << line })

    tally = nil
    expect { tally = client.run(once: true) }.not_to raise_error
    expect(tally).to eq({ "stopped" => 1 })
    expect(notes.first).to match(/coordinator unavailable/)
    expect(notes.last).to match(/still unreachable/)
  end

  it "backs off between attempts rather than hammering" do
    client = described_class.new(url: dead_url, handle: "spec", give_up_after: 4)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    client.run(once: true)
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be >= 1
  end

  it "treats throttling and coordinator errors as worth retrying" do
    expect(described_class::TRANSIENT_ERRORS).to include(Errno::ECONNREFUSED, Net::ReadTimeout)
    expect(Census::AtHome::TransientResponse.ancestors).to include(StandardError)
  end

  it "reports solved-but-unreportable work instead of discarding it silently" do
    client = described_class.new(url: dead_url, handle: "spec", give_up_after: 1)
    # Register succeeds, leasing succeeds, submission is what fails.
    allow(client).to receive(:post).and_return({ client: { id: 1 } },
                                               { unit: { id: 7, kind: "shape", shape_id: "3/1",
                                                         cells: [[0, 0, 0], [0, 0, 1], [0, 0, 2]], budgets: {} } },
                                               nil)
    notes = []
    client.instance_variable_set(:@report, ->(line) { notes << line })

    expect(client.run(once: true)).to eq({ "stopped" => 1 })
    expect(notes.last).to match(/UNREPORTED/)
  end

  # Ten of twelve clients once died in the same minute because kissat could
  # not flush a proof to a full disk. A dead solver is a unit to hand back,
  # not a reason to stop volunteering.
  it "reports a solver crash as an error and keeps going" do
    client = described_class.new(url: dead_url, handle: "spec", give_up_after: 1)
    allow(client).to receive(:post).and_return({ client: { id: 1 } },
                                               { unit: { id: 7, kind: "cube", shape_id: "9/42947", cube: [1] } },
                                               { accepted: false, note: "unknown verdict error" },
                                               { unit: nil })
    allow(client).to receive(:solve_cube).and_raise(RuntimeError, "kissat failed with exit status ")
    allow(client).to receive(:sleep)
    notes = []
    client.instance_variable_set(:@report, ->(line) { notes << line })

    tally = client.run(once: true)

    expect(tally).to include("error" => 1, "rejected" => 1)
    expect(notes).to include(a_string_matching(/solver failed: kissat failed/))
  end

  describe "refuting a cube" do
    let(:contradiction) { "spec/fixtures/proof/contradiction.cnf" }
    let(:digest)        { Digest::SHA256.file(contradiction).hexdigest }

    # The formula is already cached, which is why these run against a dead
    # coordinator: a volunteer holding the formula needs nothing from it until
    # there is an answer to report.
    around do |example|
      Dir.mktmpdir do |dir|
        @proofs = File.join(dir, "proofs")
        @formulas = File.join(dir, "formulas")
        FileUtils.mkdir_p(@formulas)
        FileUtils.cp(contradiction, File.join(@formulas, "#{digest}.cnf"))
        example.run
      end
    end

    def refute(cube)
      client = described_class.new(url: dead_url, handle: "spec", proofs: @proofs, formulas: @formulas)

      client.send(:solve_cube, { id: 1, cnf_sha256: digest, cube: })
    end

    it "returns unsat with the digest and size of a real proof" do
      verdict, payload = refute([])

      expect(verdict).to eq("unsat")
      expect(payload[:proof][:sha256]).to match(/\A[0-9a-f]{64}\z/)
      expect(payload[:proof][:bytes]).to be_positive
    end

    # Once the coordinator has the bytes, the volunteer's copy is only taking
    # up disk. Fifty clients on the colo kept 17 GB of proofs it already had.
    it "deletes its copy of a proof once the coordinator has accepted it" do
      client = described_class.new(url: dead_url, handle: "spec", proofs: @proofs, formulas: @formulas)
      FileUtils.mkdir_p(@proofs)
      File.binwrite(File.join(@proofs, "#{digest}.drat"), "a\x02\x00")
      allow(client).to receive(:post_proof).and_return({ accepted: true, note: "proof stored, queued for checking" })
      tally = Hash.new(0)

      client.send(:hand_over, [digest], tally)

      expect(tally).to eq({ "proof delivered" => 1 })
      expect(File).not_to exist(File.join(@proofs, "#{digest}.drat"))
    end

    it "keeps its copy when the coordinator refuses it" do
      client = described_class.new(url: dead_url, handle: "spec", proofs: @proofs, formulas: @formulas)
      FileUtils.mkdir_p(@proofs)
      File.binwrite(File.join(@proofs, "#{digest}.drat"), "a\x02\x00")
      allow(client).to receive(:post_proof).and_return({ accepted: false, note: "bytes hash to something else" })

      client.send(:hand_over, [digest], Hash.new(0))

      expect(File).to exist(File.join(@proofs, "#{digest}.drat"))
    end

    # Fifty clients on one box share this cache. A formula must appear under
    # its name all at once or not at all, never half written.
    it "lands a fetched formula in the cache whole, leaving nothing half written behind" do
      FileUtils.rm(File.join(@formulas, "#{digest}.cnf"))
      client = described_class.new(url: dead_url, handle: "spec", proofs: @proofs, formulas: @formulas)
      allow(client).to receive(:fetch).and_return(File.binread(contradiction))

      path = client.send(:formula_for, { id: 1, cnf_sha256: digest })

      expect(path).to eq(File.join(@formulas, "#{digest}.cnf"))
      expect(Digest::SHA256.file(path).hexdigest).to eq(digest)
      expect(Dir.children(@formulas)).to eq(["#{digest}.cnf"])
    end

    it "keeps the proof under its own digest, so it can be handed over later" do
      _verdict, payload = refute([])
      kept = File.join(@proofs, "#{payload[:proof][:sha256]}.drat")

      expect(File.size(kept)).to eq(payload[:proof][:bytes])
      expect(Digest::SHA256.file(kept).hexdigest).to eq(payload[:proof][:sha256])
    end

    # The coordinator is the one that decides, so what the client returns has
    # to be the thing the coordinator accepts.
    it "returns a payload the coordinator will accept" do
      _verdict, payload = refute([])

      expect(Census::AtHome::SubmissionGuard.new(payload:, verdict: "unsat").rejection).to be_nil
    end
  end
end
