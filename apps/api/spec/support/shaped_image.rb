# frozen_string_literal: true

require "vips"

# A JPEG of a given size whose first half (top, or left with
# `split: :horizontal`) is white and second half black, so a crop spec
# can tell which end of the image was kept from the stored pixels.
module ShapedImage
  module_function

  def bytes(width, height, split: :vertical)
    white = split == :vertical ? [ width, height / 2 ] : [ width / 2, height ]
    canvas = Vips::Image.black(width, height, bands: 3)
    canvas.draw_rect([ 255, 255, 255 ], 0, 0, *white, fill: true).write_to_buffer(".jpg")
  end

  def tempfile(width, height, split: :vertical)
    file = Tempfile.new([ "shaped", ".jpg" ])
    file.binmode
    file.write(bytes(width, height, split:))
    file.rewind
    file
  end

  # Mean brightness 0..255 of a stored image.
  def brightness(bytes)
    Vips::Image.new_from_buffer(bytes, "").avg
  end
end
