# frozen_string_literal: true

RSpec.describe Census::SAT::CubeTree do
  let(:fixtures) { File.expand_path("../../fixtures/cubes", __dir__) }

  def tree(*names)
    levels = names.map { Census::SAT::CubeTree.level(File.join(fixtures, it)) }
    described_class.new(levels:)
  end

  describe "#closed?" do
    it "holds when every standing cube is partitioned and every leaf refuted" do
      expect(tree("base.icnf", "clause-split.icnf").closed?).to be(true)
    end

    it "fails when the last level leaves a cube standing" do
      expect(tree("base.icnf").closed?).to be(false)
    end

    it "fails when a standing cube is not partitioned by the next level" do
      expect(tree("base.icnf", "clause-split-gap.icnf").closed?).to be(false)
    end
  end

  describe "#failures" do
    it "names what is wrong" do
      expect(tree("base.icnf").failures).to eq(["base.icnf: 1 cube(s) still standing"])
    end

    it "is empty when closed" do
      expect(tree("base.icnf", "clause-split.icnf").failures).to eq([])
    end
  end

  describe "#leaves" do
    it "lists every refuted cube the cover rests on, with its parent chain" do
      leaves = tree("base.icnf", "clause-split.icnf").leaves
      expect(leaves.map(&:cube)).to eq([[1, 2], [1, -2], [-1, 2], [-1, -2, 5], [-1, -2, -5, 7], [-1, -2, -5, -7]])
      expect(leaves.last.parent.cube).to eq([-1, -2])
    end

    it "leaves out children of a parent that was refuted anyway" do
      levels = [
        Census::SAT::CubeTree.level(File.join(fixtures, "base.icnf")),
        Census::SAT::CubeTree.level(File.join(fixtures, "clause-split.icnf"))
      ]
      levels.first[:ledger] = double(refuted: [0, 1, 2, 3], satisfied: [])
      expect(described_class.new(levels:).leaves.size).to eq(4)
    end
  end

  describe "#split_nodes" do
    it "lists the standing cubes whose children carry the proof" do
      splits = tree("base.icnf", "clause-split.icnf").split_nodes
      expect(splits.map(&:cube)).to eq([[-1, -2]])
      expect(splits.first.children.size).to eq(3)
    end
  end
end
