require "rails_helper"

RSpec.describe UrlFetcher do
  describe ".fetch" do
    let(:url) { "https://example.com/menu" }

    it "returns the body wrapped in a Result with content_type from headers" do
      stub_request(:get, url).to_return(
        status: 200,
        body: "<html>menu html</html>",
        headers: { "Content-Type" => "text/html; charset=utf-8" }
      )

      result = described_class.fetch(url)

      expect(result.io.read).to eq("<html>menu html</html>")
      expect(result.content_type).to eq("text/html")
      expect(result.byte_size).to eq("<html>menu html</html>".bytesize)
    end

    it "sniffs PDF magic bytes when the server omits content-type" do
      stub_request(:get, url).to_return(
        status: 200,
        body: "%PDF-1.4 fake bytes",
        headers: {}
      )

      result = described_class.fetch(url)

      expect(result.content_type).to eq("application/pdf")
    end

    it "rejects non-2xx responses with FetchError" do
      stub_request(:get, url).to_return(status: 404, body: "missing")

      expect { described_class.fetch(url) }
        .to raise_error(UrlFetcher::FetchError) { |e|
          expect(e.reason).to eq("non_2xx")
          expect(e.status).to eq(404)
        }
    end

    it "rejects responses larger than MAX_BYTES" do
      stub_request(:get, url).to_return(status: 200, body: "x" * (described_class::MAX_BYTES + 1))

      expect { described_class.fetch(url) }
        .to raise_error(UrlFetcher::FetchError, /response_too_large/)
    end

    it "rejects non-http(s) URLs without making a request" do
      expect { described_class.fetch("file:///etc/passwd") }
        .to raise_error(UrlFetcher::FetchError, /invalid_url/)
    end

    it "infers a sensible filename from the URL path" do
      stub_request(:get, "https://example.com/menus/dinner.pdf").to_return(
        status: 200,
        body: "%PDF",
        headers: { "Content-Type" => "application/pdf" }
      )

      result = described_class.fetch("https://example.com/menus/dinner.pdf")

      expect(result.filename).to eq("dinner.pdf")
    end

    it "falls back to 'menu.html' when the URL has no path tail" do
      stub_request(:get, "https://example.com/").to_return(
        status: 200,
        body: "<html></html>",
        headers: { "Content-Type" => "text/html" }
      )

      expect(described_class.fetch("https://example.com/").filename).to eq("menu.html")
    end
  end
end
