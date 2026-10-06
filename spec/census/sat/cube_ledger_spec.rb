# frozen_string_literal: true

RSpec.describe Census::SAT::CubeLedger do
  let(:fixtures) { File.expand_path("../../fixtures/cubes", __dir__) }

  describe "#refuted" do
    it "lists every cube that was ever refuted, sorted" do
      ledger = described_class.new(path: File.join(fixtures, "base.icnf.results.jsonl"))
      expect(ledger.refuted).to eq([0, 1, 2])
    end
  end

  describe "#satisfied" do
    it "is empty when nothing was satisfied" do
      ledger = described_class.new(path: File.join(fixtures, "base.icnf.results.jsonl"))
      expect(ledger.satisfied).to eq([])
    end

    it "lists a satisfied cube" do
      ledger = described_class.new(path: File.join(fixtures, "satisfied.icnf.results.jsonl"))
      expect(ledger.satisfied).to eq([1])
    end
  end

  describe "#pending" do
    it "lists cubes with no decisive verdict, however many times they were tried" do
      ledger = described_class.new(path: File.join(fixtures, "base.icnf.results.jsonl"))
      expect(ledger.pending(count: 4)).to eq([3])
    end

    it "includes cubes the ledger never mentions" do
      ledger = described_class.new(path: File.join(fixtures, "base.icnf.results.jsonl"))
      expect(ledger.pending(count: 6)).to eq([3, 4, 5])
    end
  end

  describe "#entries" do
    it "keeps every line, retries included" do
      ledger = described_class.new(path: File.join(fixtures, "base.icnf.results.jsonl"))
      expect(ledger.entries.size).to eq(5)
    end
  end
end
