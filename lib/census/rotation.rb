# frozen_string_literal: true

module Census
  # One of the 24 orientation-preserving symmetries of the cubic lattice,
  # represented as an axis permutation plus per-axis signs.
  class Rotation
    def self.all
      @all ||= build_all.freeze
    end

    def self.build_all
      axis_orders = [0, 1, 2].permutation.to_a
      sign_choices = [1, -1].repeated_permutation(3).to_a
      axis_orders.product(sign_choices)
                 .map { |axes, signs| new(axes:, signs:) }
                 .select(&:proper?)
    end

    attr_reader :axes, :signs

    def initialize(axes:, signs:)
      @axes = axes
      @signs = signs
    end

    def apply(cell)
      axes.zip(signs).map { |axis, sign| sign * cell[axis] }
    end

    def proper? = determinant == 1

    AXIS_NAMES = %w[x y z].freeze

    # Where each new coordinate comes from, as "y" or "-z". The first entry
    # is the new x: ["y", "-z", "-x"] reads "new x = y, new y = -z, new z = -x".
    def images = axes.zip(signs).map { |axis, sign| "#{'-' if sign.negative?}#{AXIS_NAMES[axis]}" }

    # The turn in degrees: 0, 90, 120, or 180.
    def angle
      case trace
      when 3 then 0
      when 1 then 90
      when 0 then 120
      when -1 then 180
      end
    end

    # The axis of the turn as a lattice direction with entries -1, 0, 1, the
    # angle measured right-handed about it. Zero for the identity.
    def axis
      return [0, 0, 0] if angle.zero?

      vector = angle == 180 ? fixed_direction : antisymmetric_part
      largest = vector.map(&:abs).max
      vector.map { it / largest }
    end

    private

    def matrix = (0..2).map { |row| (0..2).map { |column| column == axes[row] ? signs[row] : 0 } }

    def trace = (0..2).sum { matrix[it][it] }

    # Twice the sine of the angle times the axis, for turns short of a half turn.
    def antisymmetric_part
      m = matrix
      [m[2][1] - m[1][2], m[0][2] - m[2][0], m[1][0] - m[0][1]]
    end

    # A direction the half turn leaves alone: the first nonzero column of M + I.
    def fixed_direction
      m = matrix
      (0..2).map { |column| (0..2).map { |row| m[row][column] + (row == column ? 1 : 0) } }.find { it.any?(&:nonzero?) }
    end

    def determinant = permutation_sign * signs.reduce(:*)

    def permutation_sign
      inversions = axes.combination(2).count { |earlier, later| earlier > later }
      inversions.even? ? 1 : -1
    end
  end
end
