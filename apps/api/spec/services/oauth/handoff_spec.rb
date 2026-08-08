require "rails_helper"

# The digest is what makes an approval mean one specific grant. The full
# flow is exercised in spec/requests/oauth_flow_spec.rb; this pins the
# rule the flow depends on, at the level where a mistake is invisible.
RSpec.describe Oauth::Handoff do
  def url(overrides = {})
    query = { client_id: "abc", redirect_uri: "https://claude.ai/cb", scope: "discovery:read" }
            .merge(overrides).compact.to_query
    "http://www.example.com/oauth/authorize?#{query}"
  end

  describe ".binding_digest" do
    it "is stable across parameter order" do
      a = "http://www.example.com/oauth/authorize?client_id=abc&scope=discovery%3Aread"
      b = "http://www.example.com/oauth/authorize?scope=discovery%3Aread&client_id=abc"

      expect(described_class.binding_digest(URI.parse(a))).to eq(described_class.binding_digest(URI.parse(b)))
    end

    it "ignores the handoff itself, which is added after the digest exists" do
      expect(described_class.binding_digest(URI.parse("#{url}&handoff=whatever")))
        .to eq(described_class.binding_digest(URI.parse(url)))
    end

    # Not an allow-list, on purpose: a parameter added later — a new PKCE
    # method, an RFC 8707 `resource` — must fall inside the binding
    # without anyone remembering to add it.
    it "changes when any other parameter changes" do
      base = described_class.binding_digest(URI.parse(url))

      expect(described_class.binding_digest(URI.parse(url(scope: "users:write")))).not_to eq(base)
      expect(described_class.binding_digest(URI.parse(url(redirect_uri: "https://evil.test/cb")))).not_to eq(base)
      expect(described_class.binding_digest(URI.parse(url(resource: "https://elsewhere.test/mcp")))).not_to eq(base)
    end
  end

  describe ".authorize_uri!" do
    let(:origin) { "http://www.example.com" }

    it "accepts our own authorize endpoint" do
      expect { described_class.authorize_uri!(url, origin: origin) }.not_to raise_error
    end

    # A handoff is a signed capability. Minting one for a URL on someone
    # else's host would both sign a digest they chose and hand them the
    # token, so the path alone is not enough.
    it "refuses the same path on another host" do
      expect { described_class.authorize_uri!("https://evil.test/oauth/authorize?client_id=abc", origin: origin) }
        .to raise_error(described_class::InvalidReturnTo)
    end

    it "refuses another path on our host" do
      expect { described_class.authorize_uri!("http://www.example.com/api/v1/me", origin: origin) }
        .to raise_error(described_class::InvalidReturnTo)
    end

    it "refuses something that is not a URL at all" do
      expect { described_class.authorize_uri!("http://[::1", origin: origin) }
        .to raise_error(described_class::InvalidReturnTo)
    end
  end
end
