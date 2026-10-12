require "rails_helper"

RSpec.describe Ingestion::HtmlText do
  it "decodes a page with no declared charset as UTF-8, so allergen words survive" do
    html = "<html><body><p>Jalapeño poppers with béarnaise</p></body></html>".b

    expect(described_class.call(html)).to include("Jalapeño", "béarnaise")
  end

  it "keeps an undeclared UTF-8 page as UTF-8 when one stray byte is invalid" do
    html = "<html><body><p>Jalapeño béarnaise</p>".b + "\xFF".b + "</body></html>".b

    expect(described_class.call(html)).to include("Jalapeño béarnaise")
  end

  it "honours a page's declared non-UTF-8 charset" do
    html = "<html><head><meta charset=\"windows-1252\"></head><body><p>Crème brûlée</p></body></html>"
             .encode("Windows-1252").b

    expect(described_class.call(html)).to include("Crème brûlée")
  end

  it "ignores a commented-out charset declaration" do
    html = "<html><head><!-- <meta charset=\"windows-1252\"> --></head><body><p>Jalapeño</p></body></html>".b

    expect(described_class.call(html)).to include("Jalapeño")
  end

  it "honours a charset declared through http-equiv" do
    html = "<html><head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=windows-1252\"></head>" \
           "<body><p>Crème brûlée</p></body></html>"

    expect(described_class.call(html.encode("Windows-1252").b)).to include("Crème brûlée")
  end

  it "keeps a dish name and its price apart when cells sit side by side" do
    html = "<table><tr><td>Hummus</td><td>$8</td></tr></table><span>Falafel</span><span>9</span>"

    text = described_class.call(html)
    expect(text).to include("Hummus $8")
    expect(text).to include("Falafel 9")
    expect(described_class.call("<h3>Hummus<span>$8</span></h3>")).to include("Hummus $8")
  end

  it "keeps schema.org Menu JSON-LD in its array and URL forms, and drops other JSON-LD" do
    html = <<~HTML
      <script type="application/ld+json">{"@type":["Restaurant","Menu"],"name":"A"}</script>
      <script type="application/ld+json">{"@type":"http://schema.org/MenuSection","name":"B"}</script>
      <script type="application/ld+json">{"@type":"BreadcrumbList","name":"C"}</script>
    HTML

    text = described_class.call(html)
    expect(text).to include('"name":"A"', '"name":"B"')
    expect(text).not_to include("BreadcrumbList")
  end

  it "treats XML that is really HTML as HTML, and other XML as text" do
    expect(described_class.html?("application/xml", "<!DOCTYPE html><html></html>")).to be(true)
    expect(described_class.html?("application/xml", "<?xml version='1.0'?><menu/>")).to be(false)
    expect(described_class.html?("text/html; charset=utf-8", "")).to be(true)
  end
end
