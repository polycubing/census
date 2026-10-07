# frozen_string_literal: true

RSpec.describe Census::SAT::DratTrim, :checker do
  let(:contradiction) { "spec/fixtures/proof/contradiction.cnf" }
  let(:proof)         { "spec/fixtures/proof/contradiction.drat" }
  let(:satisfiable)   { "spec/fixtures/proof/satisfiable.cnf" }

  it "verifies a real proof against the formula it refutes" do
    result = described_class.check(cnf_path: contradiction, proof_path: proof)

    expect(result).to be_verified
    expect(result.summary).to eq("s VERIFIED")
  end

  # The whole point of checking: a proof is only evidence about its own
  # formula. Pointed at a satisfiable one, it must not verify.
  it "refuses a proof aimed at a formula it does not refute" do
    result = described_class.check(cnf_path: satisfiable, proof_path: proof)

    expect(result).not_to be_verified
  end

  it "keeps the checker's output whole, as the audit trail" do
    result = described_class.check(cnf_path: contradiction, proof_path: proof)

    expect(result.output).to include("verification time")
  end

  # "We could not check" and "it is wrong" are different answers, and
  # collapsing them would let a broken coordinator quietly reject good work.
  it "raises rather than reporting unverified when the checker is absent" do
    allow(described_class).to receive(:available?).and_return(false)

    expect { described_class.check(cnf_path: contradiction, proof_path: proof) }
      .to raise_error(described_class::Missing, /drat-trim not found/)
  end

  # drat-trim guesses binary or text from a proof's first twelve bytes, and a
  # binary proof that happens to start with twelve printable bytes gets read
  # as text and fails. We decide from the first byte and say so.
  describe "proof format" do
    let(:text_proof) { "spec/fixtures/proof/contradiction.text.drat" }

    it "recognises kissat's binary format" do
      expect(described_class.binary?(proof)).to be(true)
    end

    it "recognises text, which is what drat-trim itself writes" do
      expect(described_class.binary?(text_proof)).to be(false)
    end

    it "verifies the same refutation in either format" do
      expect(described_class.check(cnf_path: contradiction, proof_path: text_proof)).to be_verified
      expect(described_class.check(cnf_path: contradiction, proof_path: proof)).to be_verified
    end
  end
end
