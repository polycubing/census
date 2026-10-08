# frozen_string_literal: true

RSpec.describe Census::Rotation do
  describe ".all" do
    it "contains 24 rotations" do
      expect(described_class.all.size).to eq(24)
    end

    it "acts distinctly on a generic point" do
      images = described_class.all.map { it.apply([1, 2, 3]) }
      expect(images.uniq.size).to eq(24)
    end

    it "includes the identity" do
      images = described_class.all.map { it.apply([1, 2, 3]) }
      expect(images).to include([1, 2, 3])
    end

    it "excludes reflections" do
      images = described_class.all.map { it.apply([1, 2, 3]) }
      expect(images).not_to include([-1, 2, 3])
    end
  end
end

RSpec.describe Census::Rotation, "as a human reads it" do
  def rotation(index) = described_class.all.fetch(index)

  it "names where each new axis comes from" do
    expect(rotation(0).images).to eq(%w[x y z])
    expect(rotation(13).images).to eq(%w[y -z -x])
  end

  it "knows the identity" do
    expect(rotation(0).angle).to eq(0)
    expect(rotation(0).axis).to eq([0, 0, 0])
  end

  it "reads a half turn about x" do
    expect(rotation(1).angle).to eq(180)
    expect(rotation(1).axis).to eq([1, 0, 0])
  end

  it "reads a quarter turn, right-handed about the axis it names" do
    expect(rotation(4).images).to eq(%w[x z -y])
    expect(rotation(4).angle).to eq(90)
    expect(rotation(4).axis).to eq([-1, 0, 0])
  end

  it "reads a third turn about a body diagonal" do
    expect(rotation(13).angle).to eq(120)
    expect(rotation(13).axis).to eq([1, 1, -1])
  end

  it "accounts for all 24 as 1 identity, 9 about faces, 6 about edges, 8 about corners" do
    counts = described_class.all.group_by { [it.angle, it.axis.count(&:nonzero?)] }.transform_values(&:size)
    expect(counts).to eq({ [0, 0] => 1, [90, 1] => 6, [180, 1] => 3, [180, 2] => 6, [120, 3] => 8 })
  end
end

RSpec.describe Census::Rotation, "#turn" do
  it "says the turn in words" do
    turns = described_class.all.map(&:turn)
    expect(turns.values_at(0, 4, 13)).to eq(["identity", "90° about -x", "120° about +x+y-z"])
    expect(turns.uniq.size).to eq(24)
  end
end
