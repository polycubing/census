# frozen_string_literal: true

RSpec.describe Census::Assembly do
  describe ".groups_for" do
    it "makes one group per placement for a box certificate" do
      dicube = Census::Polycube.new(cells: [[0, 0, 0], [0, 0, 1]])
      certificate = Census::BoxSearch.new(shape: dicube).certificate
      groups = described_class.groups_for(certificate:, shape: dicube)
      expect(groups.size).to eq(1)
    end

    it "draws a brick-shaped block as exactly its eight lattice translates" do
      straight = Census::Polycube.new(cells: [[0, 0, 0], [0, 0, 1], [0, 0, 2]])
      certificate = Census::TorusSearch.new(shape: straight).certificate
      groups = described_class.groups_for(certificate:, shape: straight)
      expect(groups.size).to eq(8)
    end

    it "keeps replicated copies disjoint" do
      straight = Census::Polycube.new(cells: [[0, 0, 0], [0, 0, 1], [0, 0, 2]])
      certificate = Census::TorusSearch.new(shape: straight).certificate
      cells = described_class.groups_for(certificate:, shape: straight).flat_map { it[:cells] }
      expect(cells.uniq.size).to eq(cells.size)
    end

    context "with a skewed block" do
      # 7/206, the holey heptomino, as certified: four copies per block on a
      # lattice whose third vector is skewed, so eight translates alone span
      # x 0..10, y 0..12, z 0..3 and leave the row y = 6 empty.
      let(:shape) { Census::Polycube.new(cells: [[0, 0, 0], [0, 0, 1], [0, 0, 2], [0, 1, 0], [0, 1, 2], [0, 2, 0], [0, 2, 1]]) }
      let(:certificate) do
        { type: "torus", lattice: [[4, 0, 0], [0, 7, 0], [2, 1, 1]],
          placements: [{ offset: [0, 0, 0], rotation: 0 }, { offset: [1, 2, 0], rotation: 0 },
                       { offset: [2, 4, 0], rotation: 9 }, { offset: [1, 0, 0], rotation: 11 }] }
      end
      let(:groups) { described_class.groups_for(certificate:, shape:) }
      let(:cells) { groups.flat_map { it[:cells] } }

      it "covers the eight translates' box solid, exactly once" do
        counts = cells.tally
        box = (0..10).to_a.product((0..12).to_a, (0..3).to_a)
        expect(box.map { counts[it] }).to all(eq(1))
      end

      it "draws more copies than the eight translates, all within one shape-width of their box" do
        expect(groups.size).to be > 32
        low = cells.transpose.map(&:min)
        high = cells.transpose.map(&:max)
        expect(low).to all(be >= -2)
        expect(high.zip([10, 12, 3])).to all(satisfy { |value, edge| value <= edge + 2 })
      end

      it "never overlaps copies" do
        expect(cells.uniq.size).to eq(cells.size)
      end
    end
  end
end
