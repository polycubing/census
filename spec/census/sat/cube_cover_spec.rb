# frozen_string_literal: true

RSpec.describe Census::SAT::CubeCover do
  let(:fixtures) { File.expand_path("../../fixtures/cubes", __dir__) }

  def cover(name)
    cubes = Census::SAT::CubeFile.new(path: File.join(fixtures, name)).cubes
    described_class.new(cubes:)
  end

  describe "#complete?" do
    it "holds for every sign pattern over one set of variables" do
      expect(cover("base.icnf").complete?).to be(true)
    end

    it "fails when a sign pattern is missing" do
      expect(cover("incomplete.icnf").complete?).to be(false)
    end
  end

  describe "#children_of" do
    it "finds the cubes that extend a parent" do
      expect(cover("clause-split.icnf").children_of([-1, -2]).size).to eq(3)
    end

    it "finds nothing for a parent no cube extends" do
      expect(cover("clause-split.icnf").children_of([1, 2])).to eq([])
    end
  end

  describe "#partitions?" do
    it "holds for a first-true split on a clause" do
      expect(cover("clause-split.icnf").partitions?([-1, -2])).to be(true)
    end

    it "holds for a sign split over extra variables" do
      expect(cover("sign-split.icnf").partitions?([-1, -2])).to be(true)
    end

    it "fails when a branch is missing" do
      expect(cover("clause-split-gap.icnf").partitions?([-1, -2])).to be(false)
    end

    it "fails for a parent with no children" do
      expect(cover("clause-split.icnf").partitions?([1, 2])).to be(false)
    end
  end
end
