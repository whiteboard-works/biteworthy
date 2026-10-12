require "rails_helper"

RSpec.describe Ingestion::ExtractMenuPrompt do
  # Anthropic's vision `image` block only accepts jpeg/png/gif/webp, so
  # PDFs and text (URL scrapes arrive as text/html, pasted menus as
  # text/plain) must route to document/text blocks instead. The actual
  # block bytes are AnthropicClient's job (tested there); here we only
  # assert the routing.
  let(:client) do
    Class.new do
      def image_block(_blob) = { type: "image" }
      def document_block(_blob) = { type: "document" }
    end.new
  end

  def blob(content_type, bytes = "x")
    instance_double(ActiveStorage::Blob, content_type: content_type, download: bytes)
  end

  def input_blocks(*blobs)
    described_class.user_messages(client, blobs).first[:content]
  end

  it "routes jpeg/png/gif/webp to image blocks" do
    %w[image/jpeg image/png image/gif image/webp].each do |ct|
      expect(input_blocks(blob(ct)).first).to include(type: "image")
    end
  end

  it "routes application/pdf to a document block, not an image" do
    expect(input_blocks(blob("application/pdf", "%PDF")).first).to include(type: "document")
  end

  it "routes text/html (URL scrape) and text/plain (paste) to text blocks with the content" do
    %w[text/html text/plain].each do |ct|
      block = input_blocks(blob(ct, "Menu\nHummus 8")).first
      expect(block[:type]).to eq("text")
      expect(block[:text]).to include("Hummus")
    end
  end

  # salsaleedos.net/menus is 2.2 MB of HTML for ~10 KB of menu; sending it
  # raw hit "prompt is too long: 1068223 tokens". Scripts, styles, and
  # markup are dropped; schema.org JSON-LD is kept, since some sites put
  # the whole menu there.
  it "sends an HTML page's visible text and JSON-LD, not its scripts or markup" do
    html = <<~HTML
      <html><head><style>.x{color:red}</style><script>var blob = "#{'x' * 5000}";</script>
      <script type="application/ld+json">{"@type":"Menu","name":"Dinner"}</script>
      <script type="application/ld+json">{"@type":"ImageObject","url":"x.jpg"}</script></head>
      <body><h1>Menu</h1><p>Hummus <b>8</b></p></body></html>
    HTML
    text = input_blocks(blob("text/html", html)).first[:text]

    expect(text).to include("Hummus", "8", '"@type":"Menu"')
    expect(text).not_to include("var blob", "color:red", "<p>", "ImageObject")
  end

  it "routes application/xml to a text block (often misreported HTML)" do
    block = input_blocks(blob("application/xml", "<html><body>Menu</body></html>")).first
    expect(block[:type]).to eq("text")
    expect(block[:text]).to include("Menu")
  end

  it "appends the short instruction after the inputs" do
    expect(input_blocks(blob("image/jpeg")).last)
      .to include(type: "text", text: described_class::USER_INSTRUCTIONS)
  end
end
