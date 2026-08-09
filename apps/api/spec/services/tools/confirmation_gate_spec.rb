require "rails_helper"

# The gate that stops an allergen leaving someone's avoid list without
# them saying so.
#
# It was declared on the tool from C2 and read only by `Chat::AgentLoop`,
# which made it a property of one front door: the same call arriving over
# MCP — from an OAuth client holding `profile:write` — removed the
# allergen with nothing asked. `Tools::Base` claims to be the one place a
# call is authorized "for both front doors"; these are what make that true
# of confirmation.
RSpec.describe "argument-gated confirmation" do
  include ActiveSupport::Testing::TimeHelpers

  let(:user)  { create(:user) }
  let(:other) { create(:user) }

  let!(:peanut) { create(:ingredient, name: "Peanut", slug: "nut-peanut", path: "nut.peanut") }
  let!(:dairy)  { create(:ingredient, name: "Cheddar", slug: "dairy-cheddar", path: "dairy.cheddar") }

  def call(as: user, **args)
    Tools::Profile::UpdateAvoidLists.call(server_context: { user_id: as.id }, **args)
  end

  def payload(response) = response.to_h[:structuredContent]

  before { user.profile.update!(avoid_ingredient_ids: [peanut.id, dairy.id]) }

  describe "the first call" do
    it "refuses the removal and changes nothing" do
      response = call(remove_ingredients: ["nut-peanut"])

      expect(response.to_h[:isError]).to be(true)
      expect(payload(response)[:error]).to eq("confirmation_required")
      expect(user.profile.reload.avoid_ingredient_ids).to contain_exactly(peanut.id, dairy.id)
    end

    # The sentence is the product here. A model asked to compose its own
    # would be phrasing the question it wants answered yes, and the tool
    # declares it precisely so that cannot happen.
    it "hands back the declared sentence, not one the model composed" do
      response = call(remove_ingredients: ["nut-peanut"])

      expect(payload(response)[:prompt])
        .to eq(Tools::Profile::UpdateAvoidLists.confirmation_prompt_for(remove_ingredients: ["nut-peanut"]))
      expect(payload(response)[:prompt]).to include("nut-peanut")
      expect(payload(response)[:prompt]).to include("start showing as safe")
    end

    it "carries a token" do
      expect(payload(call(remove_ingredients: ["nut-peanut"]))[:confirmation_token]).to be_present
    end
  end

  describe "the second call" do
    it "goes through with the token from the first" do
      token = payload(call(remove_ingredients: ["nut-peanut"]))[:confirmation_token]

      response = call(remove_ingredients: ["nut-peanut"], confirmation: token)

      expect(response.to_h[:isError]).to be_falsey
      expect(user.profile.reload.avoid_ingredient_ids).to eq([dairy.id])
    end

    # The whole point of binding. Without it, "yes, stop avoiding peanut"
    # is a bearer credential for any removal at all — which is the failure
    # the chat's fingerprint exists to prevent, one door over.
    it "refuses a token minted for a different removal" do
      token = payload(call(remove_ingredients: ["nut-peanut"]))[:confirmation_token]

      response = call(remove_ingredients: ["dairy-cheddar"], confirmation: token)

      expect(payload(response)[:error]).to eq("confirmation_required")
      expect(user.profile.reload.avoid_ingredient_ids).to contain_exactly(peanut.id, dairy.id)
    end

    # Approving one removal must not smuggle a second one alongside it.
    it "refuses a token when the call grew an extra removal" do
      token = payload(call(remove_ingredients: ["nut-peanut"]))[:confirmation_token]

      call(remove_ingredients: ["nut-peanut", "dairy-cheddar"], confirmation: token)

      expect(user.profile.reload.avoid_ingredient_ids).to contain_exactly(peanut.id, dairy.id)
    end

    it "refuses one person's token used against another person's profile" do
      other.profile.update!(avoid_ingredient_ids: [peanut.id])
      token = payload(call(remove_ingredients: ["nut-peanut"]))[:confirmation_token]

      call(as: other, remove_ingredients: ["nut-peanut"], confirmation: token)

      expect(other.profile.reload.avoid_ingredient_ids).to eq([peanut.id])
    end

    it "refuses a forged token rather than erroring" do
      response = call(remove_ingredients: ["nut-peanut"], confirmation: "not-a-real-token")

      expect(payload(response)[:error]).to eq("confirmation_required")
      expect(user.profile.reload.avoid_ingredient_ids).to contain_exactly(peanut.id, dairy.id)
    end

    it "refuses a token that has aged out" do
      token = payload(call(remove_ingredients: ["nut-peanut"]))[:confirmation_token]

      travel_to(Tools::Confirmation::TTL.from_now + 1.minute) do
        call(remove_ingredients: ["nut-peanut"], confirmation: token)
      end

      expect(user.profile.reload.avoid_ingredient_ids).to contain_exactly(peanut.id, dairy.id)
    end
  end

  # Friction on the safe direction is friction for nothing: someone adding
  # an allergen is being careful, and making them confirm it teaches them
  # to click through the prompt they will one day need to read.
  describe "the safe direction" do
    it "adds without asking" do
      response = call(add_ingredients: ["nut-peanut"])

      expect(response.to_h[:isError]).to be_falsey
    end

    it "applies a preset without asking, because presets only ever add" do
      create(:dietary_profile, slug: "vegan")

      expect(call(apply_preset: "vegan").to_h[:isError]).to be_falsey
    end
  end

  # `destructive_hint` is static, so an MCP client reads it and puts a
  # human in front of the call itself. Re-asking here would cost a round
  # trip and add nothing — the argument-dependent case is the one no
  # annotation can express.
  describe "tools that are always destructive" do
    it "are left to the client's own approval, not gated here" do
      admin  = create(:user, is_admin: true)
      target = create(:user)

      response = Tools::Users::SetUserRole.call(
        server_context: { user_id: admin.id }, user_id: target.id, is_admin: true
      )

      expect(response.to_h[:isError]).to be_falsey
      expect(target.reload.is_admin).to be(true)
    end
  end
end
