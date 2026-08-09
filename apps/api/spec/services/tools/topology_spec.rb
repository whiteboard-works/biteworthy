require "rails_helper"

# The topology is documentation the model reads at runtime, which makes
# it the kind of doc that can lie. These specs bind it to the real
# registry: a workflow naming a tool that does not exist, or one the
# caller cannot run, is a failure rather than a stale line in a file.
RSpec.describe Tools::Topology do
  let(:anonymous) { Tools::Context.new({}) }
  let(:signed_in) { Tools::Context.new({ user_id: create(:user).id }) }
  let(:admin)     { Tools::Context.new({ user_id: create(:user, is_admin: true).id }) }

  it "names only tools that actually exist" do
    named = described_class::WORKFLOWS.flat_map { |flow| flow[:steps] }.uniq
    missing = named.reject { |name| Tools::Registry.find(name) }

    expect(missing).to be_empty
  end

  # The invariant behind the audience filter: a workflow offered to a
  # signed-in user must not require an admin tool halfway through, or the
  # model plans a route that dead-ends in `forbidden`.
  it "declares an audience that covers every step of the workflow" do
    described_class::WORKFLOWS.each do |flow|
      too_privileged = flow[:steps].filter_map do |name|
        tool = Tools::Registry.find(name)
        tool.name_value if rank(tool.audience) > rank(flow[:audience])
      end

      expect(too_privileged).to be_empty, "#{flow[:name]} claims :#{flow[:audience]} but needs #{too_privileged}"
    end
  end

  it "summarizes every registered domain" do
    expect(Tools::Registry::DOMAINS.keys - described_class::DOMAIN_SUMMARIES.keys).to be_empty
  end

  describe ".for" do
    it "offers an anonymous caller only the workflows they can run" do
      names = described_class.for(anonymous)[:workflows].map { |flow| flow[:name] }

      expect(names).to eq(["Find something this person can eat"])
    end

    it "adds the signed-in workflows once there is a user" do
      names = described_class.for(signed_in)[:workflows].map { |flow| flow[:name] }

      expect(names).to include("Scan a menu into the database", "Report data that is wrong")
      expect(names).not_to include("Moderate")
    end

    it "gives an admin every workflow" do
      expect(described_class.for(admin)[:workflows].size).to eq(described_class::WORKFLOWS.size)
    end

    # Same filter as tools/list. A domain whose tools are all hidden must
    # not show up as an empty heading.
    # `suggestions` is here on the strength of `suggest_correction` alone
    # — an anonymous reader can report bad data, but cannot read or
    # resolve the queue.
    it "lists no domain an anonymous caller has no tools in" do
      domains = described_class.for(anonymous)[:domains]

      expect(domains.map { |d| d[:name] })
        .to contain_exactly(:meta, :discovery, :reviews, :suggestions)
      expect(domains).to all(satisfy { |d| d[:tools].any? })
      expect(domains.find { |d| d[:name] == :suggestions }[:tools])
        .to contain_exactly("suggest_correction")
    end

    it "never names a tool the caller cannot call" do
      offered = described_class.for(signed_in)[:domains].flat_map { |d| d[:tools] }
      admin_only = Tools::Registry.all.select { |t| t.audience == :admin }.map(&:name_value)

      expect(offered & admin_only).to be_empty
    end
  end

  describe ".markdown" do
    it "renders the workflows as ordered tool sequences" do
      text = described_class.markdown(admin)

      expect(text).to include("search_restaurants → get_menu → explain_item")
      expect(text).to include("# Biteworthy tool map")
    end
  end

  describe Tools::Meta::DescribeCapabilities do
    def payload(response) = response.to_h[:structuredContent]

    it "answers anonymously with the public map" do
      response = described_class.call(server_context: {})

      expect(payload(response)[:workflows].size).to eq(1)
    end

    it "narrows to one domain" do
      response = described_class.call(server_context: { user_id: create(:user).id }, domain: "ingestion")

      expect(payload(response)[:domain][:name]).to eq(:ingestion)
      expect(payload(response)[:workflows].map { |f| f[:name] }).to include("Scan a menu into the database")
    end

    # Asking for a domain you cannot see must read as "not for you", not
    # as a broken tool.
    it "explains a domain the caller cannot see instead of leaking that it exists" do
      response = described_class.call(server_context: {}, domain: "taxonomy")

      expect(payload(response)[:error]).to eq("invalid_argument")
      expect(payload(response)[:message]).to include("available to you")
    end
  end

  describe Tools::TopologyResource do
    it "serves the map as markdown at a stable uri" do
      contents = described_class.contents(server_context: {}).to_h

      expect(contents[:uri]).to eq("biteworthy://topology")
      expect(contents[:mimeType]).to eq("text/markdown")
      expect(contents[:text]).to include("## Workflows")
    end

    it "filters by the reader's audience, like the tool does" do
      anonymous_text = described_class.contents(server_context: {}).to_h[:text]
      admin_text = described_class.contents(server_context: { user_id: create(:user, is_admin: true).id })
                                  .to_h[:text]

      expect(anonymous_text).not_to include("moderate_review")
      expect(admin_text).to include("moderate_review")
    end
  end

  def rank(audience)
    { public: 0, user: 1, admin: 2 }.fetch(audience)
  end
end
