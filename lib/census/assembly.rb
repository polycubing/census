# frozen_string_literal: true

module Census
  # Turns a tiling certificate into copy groups for OBJ assembly: box
  # placements as-is, torus placements as a solid chunk of the tiling.
  #
  # The chunk starts from a 2x2x2 block of lattice translates. When the block
  # is a brick, that is the chunk. When the lattice is skewed, the eight
  # translates leave gaps between them, so the window grows by one shape
  # reach (its longest side less one) on every side and every copy that fits inside is drawn: the eight
  # translates' box comes out solid and the edge beyond it ragged, the way a
  # cut through the real tiling is.
  class Assembly
    def self.groups_for(certificate:, shape:)
      case certificate[:type]
      when "box"   then box_groups(certificate, shape)
      when "torus" then torus_groups(certificate, shape)
      else []
      end
    end

    def self.box_groups(certificate, shape)
      certificate[:placements].each_with_index.map do |placement, index|
        { name: "copy_#{index + 1}", cells: placed_cells(placement, shape) }
      end
    end

    def self.torus_groups(certificate, shape)
      copies = certificate[:placements].map { placed_cells(it, shape) }
      basis = certificate[:lattice]
      block = lattice_shifts(basis).flat_map { |shift| copies.map { |cells| translate(cells, shift) } }
      low, high = bounds(block.flatten(1))
      return name_groups(block) if block.sum(&:size) == volume(low, high)

      reach = shape.cells.transpose.map { it.max - it.min }.max
      window_low = low.map { it - reach }
      window_high = high.map { it + reach }
      chunk = []
      coefficients = (-6..6).to_a
      coefficients.product(coefficients, coefficients) do |a, b, c|
        shift = (0..2).map { (a * basis[0][it]) + (b * basis[1][it]) + (c * basis[2][it]) }
        next unless shift.zip(window_low, window_high).all? { |value, from, to| value.between?(from - reach, to) }

        copies.each do |cells|
          moved = translate(cells, shift)
          chunk << moved if moved.all? { |cell| cell.zip(window_low, window_high).all? { |value, from, to| value.between?(from, to) } }
        end
      end
      assert_solid(chunk, low, high)
      name_groups(chunk)
    end

    def self.lattice_shifts(basis)
      [0, 1].product([0, 1], [0, 1]).map do |a, b, c|
        (0..2).map { (a * basis[0][it]) + (b * basis[1][it]) + (c * basis[2][it]) }
      end
    end

    def self.placed_cells(placement, shape)
      rotation = Rotation.all.fetch(placement[:rotation])
      shape.rotated(rotation).cells.map { |cell| cell.zip(placement[:offset]).map(&:sum) }
    end

    def self.translate(cells, shift) = cells.map { |cell| cell.zip(shift).map(&:sum) }

    def self.bounds(cells) = [cells.transpose.map(&:min), cells.transpose.map(&:max)]

    def self.volume(low, high) = low.zip(high).reduce(1) { |product, (from, to)| product * (to - from + 1) }

    def self.name_groups(copies) = copies.each_with_index.map { |cells, index| { name: "copy_#{index + 1}", cells: } }

    # Every cell of the eight translates' box must be covered exactly once by
    # the copies drawn, or the chunk would show a gap the tiling does not have.
    def self.assert_solid(chunk, low, high)
      counts = chunk.flatten(1).tally
      (low[0]..high[0]).each do |x|
        (low[1]..high[1]).each do |y|
          (low[2]..high[2]).each do |z|
            raise "tiling chunk is not solid at #{[x, y, z]} (covered #{counts[[x, y, z]].to_i} times)" unless counts[[x, y, z]] == 1
          end
        end
      end
    end
  end
end
