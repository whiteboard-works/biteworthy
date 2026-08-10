require "rails_helper"

# The four gates, one call at a time.
#
# These are the unit-level statements about what each mode means; the
# end-to-end proof that the loop honours them — and that nothing is
# actually written when a mode says no — lives in `agent_loop_spec.rb`.
RSpec.describe Chat::ModePolicy do
  # Real tool classes rather than doubles. The whole point of the policy
  # is that it reads the annotations the tools already declare, and a
  # double would let those declarations change underneath it.
  let(:read_only)     { Tools::Discovery::GetRestaurant }
  let(:plain_write)   { Tools::Restaurants::CreateRestaurant }
  let(:gated_write)   { Tools::Profile::UpdateAvoidLists }
  let(:unrecoverable) { Tools::Reviews::DeleteReview }
  let(:structure)     { Tools::Structure::EditMenuStructure }

  def decide(mode, tool, args = {}, skip: false)
    described_class.new(mode, skip_confirmations: skip).decide(tool, args)
  end

  describe "planning" do
    it "runs a read" do
      expect(decide("planning", read_only)).to eq(:run)
    end

    # Refused rather than parked. A confirmation would offer to do the
    # thing the user just said not to do this turn.
    it "refuses every write, gated or not" do
      expect(decide("planning", plain_write)).to eq(:refuse)
      expect(decide("planning", gated_write, { add_ingredients: [ "nut-peanut" ] })).to eq(:refuse)
      expect(decide("planning", unrecoverable)).to eq(:refuse)
    end

    # An unknown tool cannot prove it only reads. The other modes hand it
    # to `execute`, which answers with a not-found the model can act on;
    # planning is the one mode that has to decide something about it.
    it "refuses a tool it cannot look up" do
      expect(decide("planning", nil)).to eq(:refuse)
    end

    # `skip_confirmations` is a standing answer to "may this run without
    # asking". Planning is not asking — it is a scope for the turn, and a
    # super admin who chose it meant it.
    it "is not overridden by skip_confirmations" do
      expect(decide("planning", unrecoverable, {}, skip: true)).to eq(:refuse)
    end
  end

  describe "manual" do
    it "runs reads and ungated writes" do
      expect(decide("manual", read_only)).to eq(:run)
      expect(decide("manual", plain_write)).to eq(:run)
    end

    it "parks a destructive call" do
      expect(decide("manual", unrecoverable)).to eq(:park)
    end

    # The case no annotation can express: adding an avoid is safe, and
    # removing one un-hides dishes for someone who told us not to show
    # them.
    it "parks on the arguments when the tool gates on them" do
      expect(decide("manual", gated_write, { add_ingredients: [ "nut-peanut" ] })).to eq(:run)
      expect(decide("manual", gated_write, { remove_ingredients: [ "nut-peanut" ] })).to eq(:park)
    end

    it "runs everything for a caller with skip_confirmations" do
      expect(decide("manual", unrecoverable, {}, skip: true)).to eq(:run)
    end
  end

  describe "accept_edits" do
    # The standing yes. These are the calls that made the rung worth
    # having — a menu correction session should not ask twice a minute.
    it "runs the edits manual would have parked" do
      expect(decide("accept_edits", gated_write, { remove_ingredients: [ "nut-peanut" ] })).to eq(:run)
      expect(decide("accept_edits", Tools::Items::EditItem)).to eq(:run)
    end

    # The line is recoverability, not blast radius: an edit is fixed by
    # editing again, and these are not.
    it "still parks a call no later edit can undo" do
      expect(decide("accept_edits", unrecoverable)).to eq(:park)
      expect(decide("accept_edits", Tools::Users::SetUserRole)).to eq(:park)
    end

    # One tool, both answers — which is why the declaration takes a block
    # rather than a flag.
    it "reads the arguments when a tool both edits and deletes" do
      expect(decide("accept_edits", structure, { action: "create_section" })).to eq(:run)
      expect(decide("accept_edits", structure, { action: "delete_menu" })).to eq(:park)
    end

    # Accepting a correction is not an edit the accepter authored: a
    # stranger wrote it, and an accepted `remove_ingredient` un-hides that
    # dish for **everyone** avoiding the ingredient. Rejecting only closes
    # the row, so it stays an ordinary edit.
    it "still stops before accepting a stranger's correction" do
      suggestion = Tools::Suggestions::ResolveSuggestion
      expect(decide("accept_edits", suggestion, { decision: "accepted" })).to eq(:park)
      expect(decide("accept_edits", suggestion, { decision: "rejected" })).to eq(:run)
    end

    # The tool's own description says it cannot be undone, and what it
    # buys is visibility to people filtering for a real allergy.
    it "still stops before promoting a restaurant's data to confirmed" do
      expect(decide("accept_edits", Tools::Restaurants::ConfirmRestaurantData)).to eq(:park)
    end

    # The default has to fail closed. A standing grant cannot cover a
    # destructive call nobody has classified — including one added to the
    # codebase long after the grant was designed. `registry_spec` keeps
    # the real catalogue from ever reaching this branch; this pins the
    # branch itself.
    it "parks a destructive tool that never said whether it can be undone" do
      unclassified = Class.new(Tools::Base) do
        tool_name "unclassified_write"
        annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: true)
      end

      expect(unclassified.recoverability_declared?).to be(false)
      expect(decide("accept_edits", unclassified)).to eq(:park)
    end

    it "runs a destructive tool that declared itself an ordinary edit" do
      expect(Tools::Items::EditItem.recoverability_declared?).to be(true)
      expect(decide("accept_edits", Tools::Items::EditItem)).to eq(:run)
    end
  end

  describe "auto" do
    it "parks nothing" do
      expect(decide("auto", unrecoverable)).to eq(:run)
      expect(decide("auto", Tools::Taxonomy::DeleteTaxonomyNode)).to eq(:run)
    end
  end

  # The value arrives from a client and rides in a jsonb payload that an
  # older deploy may have written. The safe reading of something we do not
  # recognise is the strictest one that still works.
  describe "an unrecognised mode" do
    it "resolves to manual rather than raising" do
      expect(described_class.resolve("yolo")).to eq("manual")
      expect(described_class.resolve(nil)).to eq("manual")
      expect(decide("yolo", unrecoverable)).to eq(:park)
    end
  end
end
