require "rails_helper"

# Forty-four tool schemas measured 21,650 cached tokens carried on every
# turn of every conversation, and a given turn uses two or three of them.
# These pin the deferral contract — including the two ways to get it wrong
# that cost a 400 on every turn rather than a worse answer.
RSpec.describe Chat::ToolCatalog do
  let(:anonymous) { Tools::Context.new({}) }
  let(:signed_in) { Tools::Context.new({ user_id: create(:user).id }) }
  let(:admin)     { Tools::Context.new({ user_id: create(:user, is_admin: true).id }) }

  def definitions(context) = described_class.definitions(context)

  def named(context, name)
    definitions(context).find { |d| d[:name] == name }
  end

  describe "the search tool" do
    # Without it, a deferred tool can never be reached.
    it "is offered to every caller" do
      [anonymous, signed_in, admin].each do |context|
        expect(definitions(context).first[:type]).to eq("tool_search_tool_regex_20251119")
      end
    end

    # The API rejects a deferred search tool — it is the one thing that
    # must always be loaded, because it is how everything else arrives.
    it "is never itself deferred" do
      expect(definitions(admin).first).not_to have_key(:defer_loading)
    end
  end

  describe "what stays resident" do
    # These open nearly every conversation: what can I eat, what do I
    # avoid, and the map to everything else.
    it "keeps discovery, profile, and meta loaded" do
      %w[get_menu search_restaurants get_profile describe_capabilities].each do |name|
        expect(named(signed_in, name)).not_to have_key(:defer_loading), "#{name} should be resident"
      end
    end

    it "defers everything else" do
      %w[set_user_role edit_menu_structure write_review moderate_review].each do |name|
        expect(named(admin, name)).to include(defer_loading: true), "#{name} should be deferred"
      end
    end

    # The whole point: a cold turn stops carrying schemas it will not use.
    it "leaves most of the catalog off the resident set" do
      resident = definitions(admin).reject { |d| d[:defer_loading] }

      expect(resident.length).to be < (Tools::Registry.all.length / 2)
    end
  end

  # The API 400s a request where every tool is deferred. Core tools are
  # :public or :user so a signed-out caller still has some — but a future
  # change to CORE_DOMAINS could quietly empty it, and the failure would be
  # every turn erroring rather than one answering badly.
  it "refuses to ship an all-deferred set rather than letting the API 400" do
    stub_const("#{described_class}::CORE_DOMAINS", [])

    expect { definitions(admin) }.to raise_error(/all-deferred/)
  end

  # Deferral must not become a second audience filter — a caller who
  # cannot use a tool should still never see it named.
  it "still hides tools the caller may not use" do
    names = definitions(signed_in).map { |d| d[:name] }

    expect(names).to include("get_menu")
    expect(names).not_to include("set_user_role")
  end
end
