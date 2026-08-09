require "rails_helper"

# Registry invariants over the REAL catalog, not a fixture. Every trap
# this file guards has already bitten once: a tool registered under no
# domain, a domain base class whose `audience` failed to inherit, two
# tools claiming the same name.
RSpec.describe Tools::Registry do
  let(:anonymous) { Tools::Context.new({}) }
  let(:signed_in) { Tools::Context.new({ user_id: create(:user).id }) }
  let(:admin)     { Tools::Context.new({ user_id: create(:user, is_admin: true).id }) }

  it "puts every registered tool in exactly one domain" do
    expect(described_class.all.select { |tool| described_class.domain_of(tool).nil? }).to be_empty
  end

  it "gives every tool a unique wire name" do
    names = described_class.all.map(&:name_value)

    expect(names.tally.select { |_, count| count > 1 }).to be_empty
  end

  it "declares a known audience on every tool" do
    expect(described_class.all.map(&:audience).uniq - %i[public user admin]).to be_empty
  end

  # The audience bug that shipped in M1: Ruby does not inherit
  # class-level ivars, so a domain base declaring `audience :user` left
  # every subclass at :public and listed write tools to anonymous
  # callers. Assert the inherited value per domain, not per class.
  describe "audience inheritance holds per domain" do
    {
      discovery:   :public,
      profile:     :user,
      ingestion:   :user,
      suggestions: :user,
      claims:      :user,
      history:     :user,
      structure:   :admin,
      items:       :admin,
      taxonomy:    :admin,
      moderation:  :admin,
      users:       :admin
    }.each do |domain, expected|
      it "keeps every #{domain} tool at :#{expected}" do
        tools = described_class::DOMAINS.fetch(domain).map { |name| Tools.const_get(name) }

        expect(tools.map(&:audience).uniq).to eq([expected])
      end
    end

    # Reviews are deliberately mixed: reading is public, writing is not.
    it "keeps only list_reviews public in the reviews domain" do
      public_reviews = described_class::DOMAINS.fetch(:reviews)
                                               .map { |name| Tools.const_get(name) }
                                               .select { |tool| tool.audience == :public }

      expect(public_reviews.map(&:name_value)).to eq(["list_reviews"])
    end

    # Restaurants is mixed too: anyone signed in can add a missing place,
    # only an admin can edit one that exists.
    it "keeps only create_restaurant at :user in the restaurants domain" do
      by_audience = described_class::DOMAINS.fetch(:restaurants)
                                            .map { |name| Tools.const_get(name) }
                                            .group_by(&:audience)

      expect(by_audience[:user].map(&:name_value)).to eq(["create_restaurant"])
      expect(by_audience[:admin].map(&:name_value)).to contain_exactly(
        "edit_restaurant", "confirm_restaurant_data"
      )
    end

    # Every admin tool must descend from AdminBase — that is the single
    # place :admin is declared, and the registry filter reads it.
    it "routes every admin tool through AdminBase" do
      admin_tools = described_class.all.select { |tool| tool.audience == :admin }

      expect(admin_tools).to all(be < Tools::AdminBase)
      expect(admin_tools.size).to be >= 12
    end
  end

  describe ".for" do
    it "offers an anonymous caller nothing that would just fail on auth" do
      expect(described_class.for(anonymous).map(&:audience).uniq).to eq([:public])
    end

    it "offers a signed-in caller the public and user tools, and no admin tools" do
      expect(described_class.for(signed_in).map(&:audience).uniq).to match_array(%i[public user])
    end

    it "offers an admin everything registered" do
      expect(described_class.for(admin).size).to eq(described_class.all.size)
    end

    # Visibility is the primary control — Base re-checks at call time only
    # as defence in depth.
    it "never lists a tool the caller could not call" do
      described_class.for(signed_in).each do |tool|
        expect(tool.audience).not_to eq(:admin), "#{tool.name_value} was offered to a non-admin"
      end
    end

    # Scope narrows the catalogue, not just the answer. A read-only OAuth
    # grant that is shown the write tools has a model pick one, fail, and
    # spend a turn learning what the list could have said — and with
    # deferred loading it pays for the schemas too.
    describe "when the credential is scoped" do
      let(:scoped_user) { create(:user) }
      let(:read_only) do
        Tools::Context.new({ user_id: scoped_user.id, scopes: ["profile:read", "discovery:read"] })
      end

      it "leaves out the write tools the grant cannot use" do
        names = described_class.for(read_only).map(&:name_value)

        expect(names).to include("get_profile", "get_menu")
        expect(names).not_to include("update_avoid_lists", "set_strictness")
      end

      it "leaves out domains the grant never mentioned" do
        expect(described_class.for(read_only).map(&:name_value)).not_to include("write_review")
      end

      # An unscoped credential is every token issued before scopes existed.
      # Narrowing those would be a silent lockout, not a safety win.
      it "leaves an unscoped caller's catalogue alone" do
        expect(described_class.for(signed_in).size).to be > described_class.for(read_only).size
      end

      # `discovery:read` is doorkeeper's default scope, so this is what an
      # OAuth client that asked for nothing in particular gets. The server
      # instructions tell it to read the map when the route is unclear; if
      # the map's own tool were scoped away, that instruction would send it
      # at a tool it cannot see.
      it "still offers the map to a credential that never asked for meta" do
        expect(described_class.for(read_only).map(&:name_value)).to include("describe_capabilities")
      end

      # Listing a tool that then refuses to run is the wasted turn the
      # exemption exists to prevent, so "is it offered" is only half the
      # assertion. The exemption lives in `Scopes`, which both the
      # catalogue and `Tools::Base` read, and this is what proves they
      # agree rather than merely happening to today.
      it "and the map it offers actually runs" do
        response = Tools::Meta::DescribeCapabilities.call(
          server_context: { user_id: scoped_user.id, scopes: ["discovery:read"] }
        )

        expect(response.to_h[:isError]).to be_falsey, response.to_h.inspect
      end
    end
  end

  describe ".find" do
    it "resolves a registered wire name" do
      expect(described_class.find("get_menu")).to eq(Tools::Discovery::GetMenu)
    end

    it "returns nil for anything else" do
      expect(described_class.find("drop_all_tables")).to be_nil
    end
  end

  # Descriptions ARE the interface — the model picks a tool almost
  # entirely from this text. A blank one is a broken tool.
  it "describes every tool in enough words to route on" do
    thin = described_class.all.select { |tool| tool.description_value.to_s.split.size < 15 }

    expect(thin.map(&:name_value)).to be_empty
  end

  # A write tool that claims read_only_hint would let a confirmation gate
  # wave it through.
  it "annotates every tool" do
    expect(described_class.all.select { |tool| tool.annotations_value.nil? }).to be_empty
  end
end
