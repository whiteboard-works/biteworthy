# frozen_string_literal: true

require "vips"

# Builds a tiny JPEG whose EXIF GPS IFD is populated, so specs can
# prove Images::StripMetadata actually drops location — convert(1) on
# the repo's progressive fixture JPEG does not write a GPS IFD.
module JpegWithGps
  module_function

  def bytes
    jpeg = Vips::Image.black(16, 16, bands: 3).write_to_buffer(".jpg")
    jpeg.byteslice(0, 2) + app1_gps + jpeg.byteslice(2..)
  end

  def tempfile
    file = Tempfile.new([ "gps", ".jpg" ])
    file.binmode
    file.write(bytes)
    file.rewind
    file
  end

  def app1_gps
    tiff = +"II".b
    tiff << [ 42 ].pack("v")
    tiff << [ 8 ].pack("V")
    tiff << [ 1 ].pack("v")
    gps_ifd_offset = 26
    tiff << [ 0x8825 ].pack("v") + [ 4 ].pack("v") + [ 1 ].pack("V") + [ gps_ifd_offset ].pack("V")
    tiff << [ 0 ].pack("V")

    data_off = 80
    lat = [ 40, 1, 26, 1, 46, 1 ].pack("V*")
    lon = [ 79, 1, 58, 1, 36, 1 ].pack("V*")
    entries = [
      [ 0x0001, 2, 2, "N\0".ljust(4, "\0").b ],
      [ 0x0002, 5, 3, data_off ],
      [ 0x0003, 2, 2, "W\0".ljust(4, "\0").b ],
      [ 0x0004, 5, 3, data_off + 24 ]
    ]
    gps = [ entries.size ].pack("v")
    entries.each do |tag, type, count, val|
      gps << [ tag ].pack("v") + [ type ].pack("v") + [ count ].pack("V")
      gps << (val.is_a?(Integer) ? [ val ].pack("V") : val.b[0, 4])
    end
    gps << [ 0 ].pack("V") << lat << lon
    tiff << gps

    payload = "Exif\0\0".b + tiff
    "\xFF\xE1".b + [ payload.bytesize + 2 ].pack("n") + payload
  end
  private_class_method :app1_gps
end
