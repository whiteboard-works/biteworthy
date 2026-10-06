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

    it "sniffs PDF magic bytes when content-type is generic octet-stream" do
      stub_request(:get, "https://example.com/menu.pdf").to_return(
        status: 200,
        body: "%PDF-1.7 binary content here",
        headers: { "Content-Type" => "application/octet-stream" }
      )

      result = described_class.fetch("https://example.com/menu.pdf")

      expect(result.content_type).to eq("application/pdf")
    end

    it "sniffs PDF magic bytes when content-type is binary/octet-stream" do
      stub_request(:get, "https://example.com/menu.pdf").to_return(
        status: 200,
        body: "%PDF-1.5 more binary",
        headers: { "Content-Type" => "binary/octet-stream" }
      )

      result = described_class.fetch("https://example.com/menu.pdf")

      expect(result.content_type).to eq("application/pdf")
    end

    it "corrects application/xml to text/html when the body is actually HTML" do
      stub_request(:get, url).to_return(
        status: 200,
        body: "<html><head><title>Menu</title></head><body>items</body></html>",
        headers: { "Content-Type" => "application/xml" }
      )

      result = described_class.fetch(url)

      expect(result.content_type).to eq("text/html")
    end

    it "detects HTML from body structure when content-type is missing" do
      stub_request(:get, url).to_return(
        status: 200,
        body: "<!DOCTYPE html><html><body>Menu items</body></html>",
        headers: {}
      )

      result = described_class.fetch(url)

      expect(result.content_type).to eq("text/html")
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

    it "rejects DoorDash without making a request" do
      expect { described_class.fetch("https://www.doordash.com/store/x") }
        .to raise_error(UrlFetcher::FetchError) { |e| expect(e.reason).to eq("forbidden_host") }
      expect(a_request(:get, /doordash/)).not_to have_been_made
    end

    it "rejects a redirect onto a Toast ordering host" do
      stub_request(:get, url).to_return(
        status: 302, headers: { "Location" => "https://www.toasttab.com/place/v3" }
      )

      expect { described_class.fetch(url) }
        .to raise_error(UrlFetcher::FetchError) { |e| expect(e.reason).to eq("forbidden_host") }
      expect(a_request(:get, /toasttab/)).not_to have_been_made
    end

    it "rejects a DoorDash white-label on a custom domain after fetch" do
      stub_request(:get, url).to_return(
        status: 200,
        headers: { "Content-Type" => "text/html", "Set-Cookie" => "dd_cx_js=1; Path=/" },
        body: '<html><script src="https://cdn.doordash.com/storefront.js"></script></html>'
      )

      expect { described_class.fetch(url) }
        .to raise_error(UrlFetcher::FetchError) { |e| expect(e.reason).to eq("forbidden_host") }
    end

    it "still fetches a restaurant page that only links out to DoorDash" do
      stub_request(:get, url).to_return(
        status: 200,
        headers: { "Content-Type" => "text/html" },
        body: '<html><body><a href="https://www.doordash.com/store/x">Order</a></body></html>'
      )

      result = described_class.fetch(url)

      expect(result.content_type).to eq("text/html")
      expect(result.io.read).to include("Order")
    end

    it "still fetches an own-site page that embeds a Toast ordering iframe" do
      stub_request(:get, url).to_return(
        status: 200,
        headers: { "Content-Type" => "text/html" },
        body: <<~HTML
          <html><body>
            <h1>Dinner menu</h1>
            <p>Brisket plate, beans, slaw.</p>
            <iframe src="https://www.toasttab.com/serious-texas/v3"></iframe>
          </body></html>
        HTML
      )

      result = described_class.fetch(url)

      expect(result.io.read).to include("Dinner menu")
    end

    it "still fetches a page that only sets a Datadog dd_cookie_test cookie" do
      stub_request(:get, url).to_return(
        status: 200,
        headers: { "Content-Type" => "text/html", "Set-Cookie" => "dd_cookie_test_x=1; Path=/" },
        body: "<html><body>Menu</body></html>"
      )

      result = described_class.fetch(url)

      expect(result.io.read).to include("Menu")
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

    describe "bot challenge detection" do
      it "detects SiteGround captcha when a .pdf URL returns HTML with sgcaptcha" do
        stub_request(:get, "https://example.com/menu.pdf").to_return(
          status: 200,
          body: '<html><body><a href="/.well-known/sgcaptcha/">Verify</a></body></html>',
          headers: { "Content-Type" => "text/html" }
        )

        expect { described_class.fetch("https://example.com/menu.pdf") }
          .to raise_error(UrlFetcher::FetchError) { |e|
            expect(e.reason).to eq("bot_challenge")
          }
      end

      it "detects Cloudflare challenge pages with specific markers" do
        stub_request(:get, "https://example.com/menu.pdf").to_return(
          status: 200,
          body: '<html><head><title>Just a moment...</title></head><body><div class="challenge-platform"></div></body></html>',
          headers: { "Content-Type" => "text/html" }
        )

        expect { described_class.fetch("https://example.com/menu.pdf") }
          .to raise_error(UrlFetcher::FetchError, /bot_challenge/)
      end

      it "detects Cloudflare __cf_chl parameter" do
        stub_request(:get, "https://example.com/menu.pdf").to_return(
          status: 200,
          body: '<html><body><form action="?__cf_chl_tk=abc"></form></body></html>',
          headers: { "Content-Type" => "text/html" }
        )

        expect { described_class.fetch("https://example.com/menu.pdf") }
          .to raise_error(UrlFetcher::FetchError, /bot_challenge/)
      end

      it "allows normal HTML pages when no .pdf extension is expected" do
        stub_request(:get, "https://example.com/menu").to_return(
          status: 200,
          body: "<html><body>Menu items here</body></html>",
          headers: { "Content-Type" => "text/html" }
        )

        expect { described_class.fetch("https://example.com/menu") }.not_to raise_error
      end

      it "does NOT flag normal menus that mention Cloudflare or security in content" do
        # A restaurant mentioning "We use Cloudflare for security" in their footer
        # should NOT be flagged as a bot challenge
        menu_with_footer = <<~HTML
          <html>
          <body>
            <h1>Our Menu</h1>
            <div class="menu">
              <h2>Appetizers</h2>
              <p>Spring Rolls - $8</p>
              <p>Hummus - $6</p>
            </div>
            <footer>
              <p>This site is protected by Cloudflare for security.</p>
            </footer>
          </body>
          </html>
        HTML

        stub_request(:get, "https://example.com/menu").to_return(
          status: 200,
          body: menu_with_footer,
          headers: { "Content-Type" => "text/html" }
        )

        expect { described_class.fetch("https://example.com/menu") }.not_to raise_error
      end

      it "raises unexpected_content_type when a .pdf returns HTML without challenge markers" do
        stub_request(:get, "https://example.com/menu.pdf").to_return(
          status: 200,
          body: "<html><body>Regular page</body></html>",
          headers: { "Content-Type" => "text/html" }
        )

        expect { described_class.fetch("https://example.com/menu.pdf") }
          .to raise_error(UrlFetcher::FetchError) { |e|
            expect(e.reason).to eq("unexpected_content_type")
          }
      end
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

      # An IPv4-mapped IPv6 address is an IPv4 address wearing a hat, and
      # Ruby reports it as `ipv4? == false` — so every one of these was
      # checked against the IPv6 list, which has no mapped range, and
      # reached its target through all of the guards above. This is the
      # bypass, written out one target at a time.
      it "rejects IPv4-mapped IPv6 addresses" do
        {
          "cloud metadata" => "[::ffff:169.254.169.254]",
          "loopback"       => "[::ffff:127.0.0.1]",
          "RFC1918"        => "[::ffff:10.0.0.1]",
          "expanded form"  => "[0:0:0:0:0:ffff:7f00:1]"
        }.each do |label, host|
          expect { described_class.fetch("http://#{host}/menu") }
            .to raise_error(UrlFetcher::FetchError, /blocked_address/), "#{label} (#{host}) got through"
        end
      end

      it "rejects the IPv6 unspecified address and the NAT64 prefix" do
        expect { described_class.fetch("http://[::]/menu") }
          .to raise_error(UrlFetcher::FetchError, /blocked_address/)
        expect { described_class.fetch("http://[64:ff9b::7f00:1]/menu") }
          .to raise_error(UrlFetcher::FetchError, /blocked_address/)
      end

      # A public IPv6 host must still work — the normalization must not
      # turn the allowlist into a blocklist of everything.
      it "still allows an ordinary IPv6 host" do
        stub_request(:get, "http://[2606:4700:4700::1111]/menu")
          .to_return(status: 200, body: "<html></html>", headers: { "Content-Type" => "text/html" })

        expect { described_class.fetch("http://[2606:4700:4700::1111]/menu") }.not_to raise_error
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
