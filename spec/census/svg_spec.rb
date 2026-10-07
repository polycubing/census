# frozen_string_literal: true

RSpec.describe Census::SVG do
  def render(cells, background: nil)
    camera = Census::Camera.new(cells:, azimuth: 30, elevation: 20, distance: 3)
    described_class.new(cells:, camera:, size: 256, background:).render
  end

  describe "#render" do
    it "renders the monocube byte-identical to the fixture" do
      expect(render([[0, 0, 0]])).to eq(File.read("spec/fixtures/monocube.svg"))
    end

    it "draws three faces of a cube" do
      expect(render([[0, 0, 0]]).scan("<polygon").size).to eq(3)
    end

    it "culls the shared face and the faces turned away" do
      expect(render([[0, 0, 0], [0, 0, 1]]).scan("<polygon").size).to eq(5)
    end

    it "gives the three visible face directions three different greys" do
      fills = render([[0, 0, 0]]).scan(/fill="(#[0-9a-f]{6})"/).flatten
      expect(fills.uniq.size).to eq(3)
    end

    it "has no background unless asked" do
      expect(render([[0, 0, 0]])).not_to include("<rect")
    end

    it "fills the whole square when given a background" do
      expect(render([[0, 0, 0]], background: "#f6f8fa")).to include(%(<rect width="100%" height="100%" fill="#f6f8fa"/>))
    end
  end
end
