require "rails_helper"

# A menu exported at print resolution runs past the 10 MB scan limit.
# These pin that Ghostscript brings such a PDF down without losing the
# page, and that every way the pass can fail answers nil rather than
# raising — the caller falls through to its usual too-large message.
RSpec.describe Pdfs::Shrink do
  # A one-page PDF drawing one JPEG at 300 dpi, written by hand so the
  # fixture needs no ImageMagick (whose PDF coder is often policy-blocked).
  def pdf_with_jpeg(jpeg, pixels:)
    points = (pixels * 72.0 / 300).round
    content = "q #{points} 0 0 #{points} 0 0 cm /Im0 Do Q"
    objects = [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 #{points} #{points}] " \
        "/Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>",
      "<< /Type /XObject /Subtype /Image /Width #{pixels} /Height #{pixels} /ColorSpace /DeviceRGB " \
        "/BitsPerComponent 8 /Filter /DCTDecode /Length #{jpeg.bytesize} >>\nstream\n#{jpeg}\nendstream",
      "<< /Length #{content.bytesize} >>\nstream\n#{content}\nendstream"
    ]
    out = +"%PDF-1.4\n"
    offsets = objects.each_with_index.map do |body, i|
      offsets_at = out.bytesize
      out << "#{i + 1} 0 obj\n#{body}\nendobj\n"
      offsets_at
    end
    xref = out.bytesize
    out << "xref\n0 #{objects.size + 1}\n0000000000 65535 f \n"
    offsets.each { |o| out << format("%010d 00000 n \n", o) }
    out << "trailer\n<< /Size #{objects.size + 1} /Root 1 0 R >>\nstartxref\n#{xref}\n%%EOF\n"
    out.b
  end

  def write_tempfile(bytes)
    file = Tempfile.new([ "menu", ".pdf" ], binmode: true)
    file.write(bytes)
    file.flush
    file
  end

  it "rewrites a print-resolution PDF into a smaller one gs can still read" do
    noise = Vips::Image.gaussnoise(2400, 2400, mean: 128, sigma: 60)
    source = write_tempfile(pdf_with_jpeg(noise.write_to_buffer(".jpg", Q: 95), pixels: 2400))

    result = described_class.call(source.path)

    expect(result).not_to be_nil
    expect(result.size).to be < File.size(source.path)
    expect(result.read(5)).to eq("%PDF-")
  ensure
    source&.close!
    result&.close!
  end

  it "returns nil when Ghostscript is not installed" do
    allow(described_class).to receive(:available?).and_return(false)
    source = write_tempfile("%PDF-1.4\n")

    expect(described_class.call(source.path)).to be_nil
  ensure
    source&.close!
  end

  it "returns nil when Ghostscript cannot read the file" do
    source = write_tempfile("this is not a pdf")

    expect(described_class.call(source.path)).to be_nil
  ensure
    source&.close!
  end

  # A PDF that is already lean comes out of pdfwrite bigger, not smaller;
  # handing that back would make an upload larger than what was sent.
  it "returns nil when the rewrite is not smaller" do
    tiny = Vips::Image.black(8, 8).write_to_buffer(".jpg")
    source = write_tempfile(pdf_with_jpeg(tiny, pixels: 8))

    expect(described_class.call(source.path)).to be_nil
  ensure
    source&.close!
  end

  it "returns nil instead of hanging on a run that overruns its time" do
    stub_const("Pdfs::Shrink::TIMEOUT_SECONDS", 0.01)
    allow(Process).to receive(:spawn).and_wrap_original do |spawn, *|
      spawn.call("sleep", "5", in: File::NULL, out: File::NULL, err: File::NULL)
    end
    source = write_tempfile("%PDF-1.4\n")

    expect(described_class.call(source.path)).to be_nil
  ensure
    source&.close!
  end
end
