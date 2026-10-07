# frozen_string_literal: true

RSpec.describe Census::Camera do
  let(:camera) { described_class.new(cells: [[0, 0, 0]], azimuth: 30, elevation: 20, distance: 3) }

  describe "#position" do
    it "sits the given number of shape widths from the shape's centre" do
      expect(camera.distance_to([0.5, 0.5, 0.5])).to be_within(1e-9).of(3)
    end

    it "scales that distance by the shape's widest extent" do
      wide = described_class.new(cells: [[0, 0, 0], [1, 0, 0], [2, 0, 0]], azimuth: 30, elevation: 20, distance: 3)
      expect(wide.distance_to([1.5, 0.5, 0.5])).to be_within(1e-9).of(9)
    end
  end

  describe "#facing?" do
    it "sees the top of a cube from above" do
      expect(camera.facing?([0, 0, 1], [0.5, 0.5, 1])).to be(true)
    end

    it "does not see the bottom" do
      expect(camera.facing?([0, 0, -1], [0.5, 0.5, 0])).to be(false)
    end
  end

  describe "#project" do
    it "draws the near edge of the top face longer than the far edge" do
      length = ->(a, b) { Math.sqrt(a.zip(b).sum { |p, q| (p - q)**2 }) }
      near = length.(camera.project([1, 0, 1]), camera.project([1, 1, 1]))
      far = length.(camera.project([0, 0, 1]), camera.project([0, 1, 1]))
      expect(near).to be > far
    end

    it "puts up on screen upward" do
      expect(camera.project([0.5, 0.5, 1]).last).to be < camera.project([0.5, 0.5, 0]).last
    end
  end
end
