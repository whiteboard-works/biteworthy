require "rails_helper"

# The one write tool in this phase that can change what a person is shown
# before they eat. Its whole design is "explicit diff, never replacement" —
# these lock that in.
RSpec.describe Tools::Profile::UpdateAvoidLists do
  let(:user) { create(:user) }

  # Eager: the tool resolves these slugs at call time, so a lazy `let`
  # would have it reject every input as unknown.
  let!(:peanut) { create(:ingredient, name: "Peanut", slug: "nut-peanut", path: "nut.peanut") }
  let!(:dairy)  { create(:ingredient, name: "Cheddar", slug: "dairy-cheddar", path: "dairy.cheddar") }
  let!(:shellfish_tag) do
    create(:tag, name: "Contains shellfish", slug: "contains-shellfish", family: "allergen")
  end

  def call(**args)
    described_class.call(server_context: { user_id: user.id }, **args)
  end

  # A removal is gated: the first call answers with a sentence and a
  # token, and only the second one actually writes. Tests that care about
  # the *effect* of a removal go through this; the gate itself is asserted
  # on its own below.
  def call_confirmed(**args)
    token = payload(call(**args))[:confirmation_token]
    described_class.call(server_context: { user_id: user.id }, confirmation: token, **args)
  end

  def payload(response) = response.to_h[:structuredContent]

  describe "adding" do
    it "adds an ingredient and reports the resulting profile in slugs" do
      response = call(add_ingredients: ["nut-peanut"])

      expect(payload(response)[:added][:ingredients]).to eq(["nut-peanut"])
      expect(payload(response)[:profile][:avoid_ingredients]).to eq(["nut-peanut"])
      expect(user.profile.reload.avoid_ingredient_ids).to eq([peanut.id])
    end

    # The failure this prevents: a model rebuilding the whole array from
    # conversation and dropping an allergen nobody happened to mention.
    it "leaves existing avoids untouched when adding a different one" do
      user.profile.update!(avoid_ingredient_ids: [peanut.id])

      call(add_ingredients: ["dairy-cheddar"])

      expect(user.profile.reload.avoid_ingredient_ids).to contain_exactly(peanut.id, dairy.id)
    end

    it "is idempotent — re-adding does not duplicate" do
      call(add_ingredients: ["nut-peanut"])
      call(add_ingredients: ["nut-peanut"])

      expect(user.profile.reload.avoid_ingredient_ids).to eq([peanut.id])
    end
  end

  describe "removing" do
    it "removes only the named slug" do
      user.profile.update!(avoid_ingredient_ids: [peanut.id, dairy.id])

      call_confirmed(remove_ingredients: ["dairy-cheddar"])

      expect(user.profile.reload.avoid_ingredient_ids).to eq([peanut.id])
    end

    # Ambiguity here would mean an allergen's fate depends on argument
    # order. Removal wins so the outcome is always the safer read of the
    # request... except it isn't safer, so it must at least be predictable.
    it "resolves a slug passed as both add and remove deterministically (removal wins)" do
      call_confirmed(add_ingredients: ["nut-peanut"], remove_ingredients: ["nut-peanut"])

      expect(user.profile.reload.avoid_ingredient_ids).to be_empty
    end
  end

  describe "slug validation" do
    it "rejects the whole call when any slug is unknown, changing nothing" do
      user.profile.update!(avoid_ingredient_ids: [peanut.id])

      response = call(add_ingredients: ["dairy-cheddar", "not-a-real-ingredient"])

      expect(response.to_h[:isError]).to be(true)
      expect(payload(response)[:message]).to match(/not-a-real-ingredient/)
      expect(payload(response)[:message]).to match(/search_taxonomy/)
      expect(user.profile.reload.avoid_ingredient_ids).to eq([peanut.id])
    end

    it "refuses a no-op call rather than reporting a successful non-change" do
      response = call

      expect(response.to_h[:isError]).to be(true)
      expect(payload(response)[:error]).to eq("invalid_argument")
    end
  end

  describe "tags" do
    it "adds tag avoids alongside ingredient avoids" do
      call(add_tags: ["contains-shellfish"], add_ingredients: ["nut-peanut"])

      expect(user.profile.reload.avoid_tag_ids).to eq([shellfish_tag.id])
      expect(user.profile.avoid_ingredient_ids).to eq([peanut.id])
    end
  end

  describe "presets" do
    let(:preset) { create(:dietary_profile, slug: "nut-free", name: "Nut free") }

    before { create(:dietary_profile_ingredient, dietary_profile: preset, ingredient: peanut) }

    # Presets are additive by contract — adopting one must never quietly
    # drop something the user added by hand.
    it "unions the preset onto what the user already avoids" do
      user.profile.update!(avoid_ingredient_ids: [dairy.id])

      call(apply_preset: "nut-free")

      expect(user.profile.reload.avoid_ingredient_ids).to contain_exactly(dairy.id, peanut.id)
      expect(user.profile.primary_dietary_profile_id).to eq(preset.id)
    end

    it "points an unknown preset slug at search_taxonomy" do
      response = call(apply_preset: "no-such-preset")

      expect(response.to_h[:isError]).to be(true)
      expect(payload(response)[:message]).to match(/search_taxonomy/)
    end
  end

  it "refuses an anonymous caller" do
    response = described_class.call(server_context: {}, add_ingredients: ["nut-peanut"])

    expect(response.to_h[:isError]).to be(true)
    expect(payload(response)[:error]).to eq("unauthorized")
  end

  # Until C2 this rule lived only as prose in `Tools::Instructions`, which
  # made the model the thing enforcing it — on the one operation whose
  # failure mode is someone eating something that hurts them.
  describe "the confirmation gate" do
    it "requires a human answer before an avoid is removed" do
      expect(described_class.requires_confirmation?(remove_ingredients: ["nut-peanut"])).to be(true)
      expect(described_class.requires_confirmation?(remove_tags: ["contains-shellfish"])).to be(true)
    end

    # Adding an allergen is the safe direction and has to stay frictionless,
    # or people stop doing it.
    it "does not gate adding, or applying a preset" do
      expect(described_class.requires_confirmation?(add_ingredients: ["nut-peanut"])).to be(false)
      expect(described_class.requires_confirmation?(apply_preset: "vegan")).to be(false)
      expect(described_class.requires_confirmation?({})).to be(false)
    end

    it "ignores an empty removal list rather than parking on nothing" do
      expect(described_class.requires_confirmation?(remove_ingredients: [])).to be(false)
      expect(described_class.requires_confirmation?(remove_ingredients: [""])).to be(false)
    end

    # The sentence a person approves is declared here, not phrased by the
    # model that is asking for the approval.
    it "names what is about to stop being hidden" do
      prompt = described_class.confirmation_prompt_for(remove_ingredients: ["nut-peanut"])

      expect(prompt).to include("nut-peanut")
      expect(prompt).to include("start showing as safe")
    end
  end
end

