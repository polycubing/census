# frozen_string_literal: true

require "tmpdir"

RSpec.describe Census::SAT::Kissat do
  describe ".solve" do
    it "returns the true variables for a satisfiable instance" do
      instance = Census::SAT::Instance.new
      first = instance.new_variable
      second = instance.new_variable
      instance.add_clause([first, second])
      instance.add_clause([-first])
      expect(described_class.solve(instance)).to eq(Set[second])
    end

    it "returns nil for an unsatisfiable instance" do
      instance = Census::SAT::Instance.new
      only = instance.new_variable
      instance.add_clause([only])
      instance.add_clause([-only])
      expect(described_class.solve(instance)).to be_nil
    end

    it "solves identically when streaming progress" do
      instance = Census::SAT::Instance.new
      first = instance.new_variable
      second = instance.new_variable
      instance.add_clause([first, second])
      instance.add_clause([-first])
      expect(described_class.solve(instance, progress: StringIO.new)).to eq(Set[second])
    end

    it "writes a DRAT proof for an unsatisfiable instance when asked" do
      instance = Census::SAT::Instance.new
      only = instance.new_variable
      instance.add_clause([only])
      instance.add_clause([-only])
      Dir.mktmpdir do |dir|
        proof_path = File.join(dir, "refutation.drat")
        described_class.solve(instance, proof_path:)
        expect(File.size(proof_path)).to be_positive
      end
    end

    it "refutes a cube by streaming the augmented formula when no proof is wanted" do
      expect(described_class.solve_cube(cnf_path: contradiction, cube: [])).to be_nil
    end

    it "writes a DRAT proof for a refuted cube when asked" do
      Dir.mktmpdir do |dir|
        proof_path = File.join(dir, "refutation.drat")

        expect(described_class.solve_cube(cnf_path: contradiction, cube: [], proof_path:)).to be_nil
        expect(File.size(proof_path)).to be_positive
      end
    end

    # The proof must refute the cube's formula, not the base one. Asserting the
    # first variable still leaves the other two clauses contradictory.
    it "writes a proof for a formula the cube made unsatisfiable" do
      Dir.mktmpdir do |dir|
        proof_path = File.join(dir, "refutation.drat")

        expect(described_class.solve_cube(cnf_path: contradiction, cube: [1], proof_path:)).to be_nil
        expect(File.size(proof_path)).to be_positive
      end
    end

    # php(12,11): twelve pigeons, eleven holes. Unsatisfiable, and famously
    # slow for a CDCL solver, which is what a cube too hard to finish looks
    # like. A third answer, neither sat nor unsat, is what makes it splittable.
    it "reports a cube it could not decide in time, rather than raising" do
      Dir.mktmpdir do |dir|
        proof_path = File.join(dir, "refutation.drat")
        pigeonhole = "spec/fixtures/proof/pigeonhole.cnf"

        expect(described_class.solve_cube(cnf_path: pigeonhole, cube: [], proof_path:, timeout: 1)).to eq(:undecided)
      end
    end
  end

  def contradiction = "spec/fixtures/proof/contradiction.cnf"
end

RSpec.describe Census::SAT::Kissat, "a proof over the cap" do
  let(:pigeonhole) { File.expand_path("../../fixtures/proof/pigeonhole.cnf", __dir__) }

  around { |example| Dir.mktmpdir { |dir| @dir = dir and example.run } }

  # The staircase's monsters wrote proofs of tens of gigabytes into /tmp
  # until the disk was full and Postgres fell over. A cube whose proof will
  # not fit is a cube to split, found out at the cap and not at the disk.
  it "stops the solver and comes back undecided" do
    proof_path = File.join(@dir, "proof.drat")
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    result = described_class.solve_cube(cnf_path: pigeonhole, cube: [], proof_path:, max_proof_bytes: 1_000_000)

    expect(result).to eq(:undecided)
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 30
  end
end
