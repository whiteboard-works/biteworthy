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

    describe "SSRF guard" do
      it "rejects literal loopback URLs" do
        expect { described_class.fetch("http://127.0.0.1/menu") }
          .to raise_error(UrlFetcher::FetchError, /blocked_address/)
      end

      it "rejects literal RFC1918 URLs" do
        expect { described_class.fetch("http://10.0.0.5/menu") }
          .to raise_error(UrlFetcher::FetchError, /blocked_address/)
        expect { described_class.fetch("http://192.168.1.1/menu") }
          .to raise_error(UrlFetcher::FetchError, /blocked_address/)
        expect { described_class.fetch("http://172.16.0.1/menu") }
          .to raise_error(UrlFetcher::FetchError, /blocked_address/)
      end

      it "rejects cloud metadata endpoint (link-local 169.254/16)" do
        expect { described_class.fetch("http://169.254.169.254/latest/meta-data/") }
          .to raise_error(UrlFetcher::FetchError, /blocked_address/)
      end

      it "rejects IPv6 loopback" do
        expect { described_class.fetch("http://[::1]/menu") }
          .to raise_error(UrlFetcher::FetchError, /blocked_address/)
      end

      it "rejects hostnames that resolve to private addresses" do
        allow(Resolv).to receive(:getaddresses).with("internal.example.com").and_return(["10.0.0.5"])

        expect { described_class.fetch("https://internal.example.com/menu") }
          .to raise_error(UrlFetcher::FetchError, /blocked_address/)
      end

      it "rejects hostnames whose any resolved address is private" do
        # Mixed-resolution attack: one public + one private. We're strict — any private = block.
        allow(Resolv).to receive(:getaddresses).with("dual.example.com").and_return(["93.184.215.14", "127.0.0.1"])

        expect { described_class.fetch("https://dual.example.com/menu") }
          .to raise_error(UrlFetcher::FetchError, /blocked_address/)
      end

      it "raises dns_failed when the host has no addresses" do
        allow(Resolv).to receive(:getaddresses).with("nx.example.com").and_return([])

        expect { described_class.fetch("https://nx.example.com/menu") }
          .to raise_error(UrlFetcher::FetchError, /dns_failed/)
      end
    end

    describe "redirects" do
      it "follows a redirect to a public host" do
        stub_request(:get, "https://example.com/menu").to_return(
          status: 302, headers: { "Location" => "https://example.com/menus/dinner.pdf" }
        )
        stub_request(:get, "https://example.com/menus/dinner.pdf").to_return(
          status: 200, body: "%PDF", headers: { "Content-Type" => "application/pdf" }
        )

        result = described_class.fetch("https://example.com/menu")

        expect(result.content_type).to eq("application/pdf")
        expect(result.filename).to eq("dinner.pdf")
      end

      it "rejects a redirect to a private address" do
        stub_request(:get, "https://example.com/menu").to_return(
          status: 302, headers: { "Location" => "http://169.254.169.254/latest/meta-data/" }
        )

        expect { described_class.fetch("https://example.com/menu") }
          .to raise_error(UrlFetcher::FetchError, /blocked_address/)
      end

      it "raises too_many_redirects after MAX_REDIRECTS hops" do
        stub_request(:get, "https://example.com/a").to_return(
          status: 302, headers: { "Location" => "https://example.com/b" }
        )
        stub_request(:get, "https://example.com/b").to_return(
          status: 302, headers: { "Location" => "https://example.com/c" }
        )
        stub_request(:get, "https://example.com/c").to_return(
          status: 302, headers: { "Location" => "https://example.com/d" }
        )
        stub_request(:get, "https://example.com/d").to_return(
          status: 302, headers: { "Location" => "https://example.com/e" }
        )

        expect { described_class.fetch("https://example.com/a") }
          .to raise_error(UrlFetcher::FetchError, /too_many_redirects/)
      end
    end
  end
end
