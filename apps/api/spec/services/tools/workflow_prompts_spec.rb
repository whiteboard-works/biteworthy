require "rails_helper"

# The topology's workflows, offered as things a client can pick before
# typing. Generated from `Topology::WORKFLOWS` rather than restated, so
# these mostly guard the generation staying honest.
RSpec.describe Tools::WorkflowPrompts do
  let(:anonymous) { Tools::Context.new({}) }
  let(:signed_in) { Tools::Context.new({ user_id: create(:user).id }) }
  let(:admin)     { Tools::Context.new({ user_id: create(:user, is_admin: true).id }) }

  it "offers one prompt per declared workflow" do
    expect(described_class.all.length).to eq(Tools::Topology::WORKFLOWS.length)
  end

  it "gives every prompt a stable, readable wire name" do
    names = described_class.all.map(&:name_value)

    expect(names).to include("scan_a_menu_into_the_database")
    expect(names.uniq.length).to eq(names.length)
    expect(names).to all(match(/\A[a-z0-9_]+\z/))
  end

  # Same rule the registry and the topology map apply: a workflow is
  # offered only to a caller who can run every step, so a client is never
  # handed a route that dead-ends in `forbidden`.
  describe "audience filtering" do
    it "offers an anonymous caller only the public workflow" do
      expect(described_class.for(anonymous).map(&:workflow_audience).uniq).to eq([:public])
    end

    it "adds the signed-in workflows once there is a user" do
      audiences = described_class.for(signed_in).map(&:workflow_audience).uniq

      expect(audiences).to contain_exactly(:public, :user)
    end

    it "gives an admin every workflow" do
      expect(described_class.for(admin).length).to eq(Tools::Topology::WORKFLOWS.length)
    end
  end

  # Audience alone stopped being the whole answer once a credential could
  # be scoped: a signed-in read-only token clears every audience check and
  # still cannot run a single write step. Offering it "Scan a menu into the
  # database" is precisely the dead-end route this filter exists to avoid.
  describe "scope filtering" do
    let(:read_only) do
      Tools::Context.new({ user_id: create(:user).id, scopes: ["discovery:read"] })
    end

    it "withholds a workflow whose steps the credential cannot run" do
      offered = described_class.for(read_only).map(&:name_value)

      expect(offered).to include("find_something_this_person_can_eat")
      expect(offered).not_to include("scan_a_menu_into_the_database",
                                     "set_up_or_adjust_what_gets_hidden")
    end

    it "offers every step of every workflow it does offer" do
      available = Tools::Registry.for(read_only).map(&:name_value)

      described_class.for(read_only).each do |prompt|
        expect(prompt.workflow_steps - available).to be_empty,
                                                    "#{prompt.name_value} names tools this caller cannot run"
      end
    end
  end

  # The failure this guards is a prompt that tells a model to call a tool
  # that does not exist — documentation lying at runtime, which is exactly
  # what the topology spec was written to prevent.
  it "names only tools that are actually registered" do
    known = Tools::Registry.all.map(&:name_value)

    described_class.all.each do |prompt|
      expect(prompt.workflow_steps - known).to be_empty, "#{prompt.name_value} names unknown tools"
    end
  end

  it "renders a message carrying the workflow's sequence and its caveat" do
    prompt = described_class.all.find { |p| p.name_value == "scan_a_menu_into_the_database" }

    text = prompt.template({}).messages.first.content.to_h[:text]

    expect(text).to include("start_menu_scan")
    expect(text).to include("accept_staged_items is the ONLY step that publishes")
  end
end
