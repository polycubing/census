# frozen_string_literal: true

module Census
  # A perspective camera looking at a polycube from a chosen angle. Azimuth
  # is the angle around z from +x toward +y, elevation the angle above the xy
  # plane, both in degrees. Distance is in multiples of the shape's widest
  # extent, so one number gives the same look on any shape.
  class Camera
    attr_reader :forward, :position, :right, :up

    def initialize(cells:, azimuth:, elevation:, distance:)
      azimuth_radians = azimuth * Math::PI / 180
      elevation_radians = elevation * Math::PI / 180
      @forward = [
        Math.cos(elevation_radians) * Math.cos(azimuth_radians),
        Math.cos(elevation_radians) * Math.sin(azimuth_radians),
        Math.sin(elevation_radians)
      ]
      @right = [-Math.sin(azimuth_radians), Math.cos(azimuth_radians), 0.0]
      @up = [
        -Math.sin(elevation_radians) * Math.cos(azimuth_radians),
        -Math.sin(elevation_radians) * Math.sin(azimuth_radians),
        Math.cos(elevation_radians)
      ]
      extents = cells.transpose.map(&:minmax)
      center = extents.map { |low, high| (low + high + 1) / 2.0 }
      width = extents.map { |low, high| high - low + 1 }.max
      @position = center.zip(forward).map { |c, f| c + f * width * distance }
    end

    # Screen coordinates, divided by depth so receding parallel edges
    # converge. v grows downward, as SVG expects.
    def project(point)
      relative = point.zip(position).map { |p, c| p - c }
      depth = -dot(relative, forward)
      [dot(relative, right) / depth, -dot(relative, up) / depth]
    end

    def facing?(normal, point)
      toward = position.zip(point).map { |c, p| c - p }
      dot(normal, toward).positive?
    end

    def distance_to(point) = Math.sqrt(point.zip(position).sum { |p, c| (p - c)**2 })

    private

    def dot(a, b) = a.zip(b).sum { |p, q| p * q }
  end
end
