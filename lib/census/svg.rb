# frozen_string_literal: true

module Census
  # Renders cells as an SVG drawing seen through a Camera: one polygon per
  # cube face that borders empty space and faces the camera, shaded by a key
  # light above and to the left of the camera, drawn farthest first so nearer
  # faces paint over farther ones.
  class SVG
    EDGE = "#2b2b2b"

    def initialize(cells:, camera:, size: 512, background: nil)
      @cells = cells
      @camera = camera
      @size = size
      @background = background
    end

    def render
      lines = [%(<svg xmlns="http://www.w3.org/2000/svg" width="#{size}" height="#{size}" viewBox="0 0 #{size} #{size}">)]
      lines << %(<rect width="100%" height="100%" fill="#{background}"/>) if background
      lines.concat(polygons.map { |fill, corners| polygon(fill, corners) })
      lines << "</svg>"
      "#{lines.join("\n")}\n"
    end

    private

    attr_reader :background, :camera, :cells, :size

    # [fill, screen corners] per visible face, farthest first, fitted into
    # the image with a margin.
    def polygons
      faces = visible_faces.map { |normal, corners| [shade(normal), corners.map { camera.project(it) }] }
      points = faces.flat_map(&:last)
      min_u, max_u = points.map(&:first).minmax
      min_v, max_v = points.map(&:last).minmax
      margin = size * 0.08
      scale = (size - (2 * margin)) / [max_u - min_u, max_v - min_v].max
      shift_u = ((size - ((max_u - min_u) * scale)) / 2) - (min_u * scale)
      shift_v = ((size - ((max_v - min_v) * scale)) / 2) - (min_v * scale)
      faces.map { |fill, corners| [fill, corners.map { |u, v| [(u * scale) + shift_u, (v * scale) + shift_v] }] }
    end

    def visible_faces
      occupied = cells.to_set
      faces = cells.flat_map do |cell|
        STL::FACES.filter_map do |face|
          next if occupied.include?(cell.zip(face[:neighbor]).map(&:sum))

          corners = face[:corners].map { |corner| cell.zip(corner).map(&:sum) }
          center = corners.transpose.map { it.sum / 4.0 }
          next unless camera.facing?(face[:normal], center)

          [camera.distance_to(center), face[:normal], corners]
        end
      end
      faces.sort_by(&:first).reverse.map { |_, normal, corners| [normal, corners] }
    end

    def polygon(fill, corners)
      points = corners.map { |u, v| "#{u.round(2)},#{v.round(2)}" }.join(" ")
      %(<polygon points="#{points}" fill="#{fill}" stroke="#{EDGE}" stroke-width="#{(size * 0.008).round(2)}" stroke-linejoin="round"/>)
    end

    def shade(normal)
      brightness = 0.5 + (0.5 * [dot(normal, light), 0].max)
      grey = (brightness * 235).round
      format("#%02x%02x%02x", grey, grey, grey)
    end

    # Key light above and to the left of the camera, so the three visible
    # face directions get three distinct greys from any angle.
    def light
      @light ||= begin
        vector = camera.forward.zip(camera.up, camera.right).map { |f, u, r| (f * 0.6) + u - (r * 0.5) }
        norm = Math.sqrt(vector.sum { it * it })
        vector.map { it / norm }
      end
    end

    def dot(a, b) = a.zip(b).sum { |p, q| p * q }
  end
end
