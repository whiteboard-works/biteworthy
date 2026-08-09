require "rails_helper"

# The taxonomy write rules used to exist in three copies — both admin
# controllers and Tools::Taxonomy::Base — and the copies had drifted.
# Only the tag controller counted `prefer_tag_ids` when deciding whether a
# node was still referenced, so a tag nobody had done anything with except
# prefer it was undeletable over REST and deletable over MCP: the same
# taxonomy answering two ways depending on which door you knocked on.
#
# These examples drive BOTH doors against one node, so either of them
# regressing away from the writer fails them. `type: :request` is for the
# HTTP half; the MCP half is a direct tool call.
RSpec.describe Taxonomy::Writer, type: :request do
  let(:admin) { create(:user, :admin) }

  def delete_via_mcp(slug)
    Tools::Taxonomy::DeleteTaxonomyNode
      .call(server_context: { user_id: admin.id }, kind: "tag", slug: slug)
      .to_h[:structuredContent]
  end

  describe "a tag referenced only by someone's prefer_tag_ids" do
    let!(:tag) { create(:tag, slug: "diet-vegan") }

    before { create(:user).profile.update!(prefer_tag_ids: [ tag.id ]) }

    # Nothing ranks by prefer_tag_ids today, but onboarding and
    # PATCH /profile write it and the account export hands it back — so
    # deleting the tag silently discards a preference the user set and can
    # still see. Both doors have to refuse, not just the one.
    it "is refused over REST, counted as a profile reference" do
      delete "/api/v1/admin/tags/#{tag.id}", headers: auth_headers_for(admin)

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body["references"]).to include("profiles" => 1)
      expect(Tag.exists?(tag.id)).to be(true)
    end

    it "is refused over MCP, with the same count" do
      payload = delete_via_mcp(tag.slug)

      expect(payload[:deleted]).to be(false)
      expect(payload[:references][:profiles]).to eq(1)
      expect(Tag.exists?(tag.id)).to be(true)
    end
  end

  # The converse, so a writer that simply refused everything could not
  # pass the pair above.
  describe "a tag nothing references" do
    it "is deleted over REST" do
      tag = create(:tag, slug: "flavor-umami")

      delete "/api/v1/admin/tags/#{tag.id}", headers: auth_headers_for(admin)

      expect(response).to have_http_status(:no_content)
      expect(Tag.exists?(tag.id)).to be(false)
    end

    it "is deleted over MCP" do
      tag = create(:tag, slug: "flavor-sweet")

      expect(delete_via_mcp(tag.slug)[:deleted]).to be(true)
      expect(Tag.exists?(tag.id)).to be(false)
    end
  end

  # The tool schemas don't expose slug/path/family, so this rail used to
  # be prose on the MCP side. Owning it in the writer makes it a backstop
  # for any caller, including a future one that forgets.
  describe "the immutable fields" do
    it "refuses a slug or path change on an ingredient" do
      ingredient = create(:ingredient, slug: "chickpea", name: "Chickpea", path: "legume_chickpea")

      expect { described_class.update!(ingredient, slug: "garbanzo", name: "Chickpeas") }
        .to raise_error(described_class::ImmutableField) { |error| expect(error.fields).to eq(%i[slug]) }
      expect(ingredient.reload).to have_attributes(slug: "chickpea", name: "Chickpea")
    end

    it "refuses a family change on a tag, which would re-classify what the filter hides" do
      tag = create(:tag, slug: "diet-keto")

      expect { described_class.update!(tag, family: "allergen") }
        .to raise_error(described_class::ImmutableField) { |error| expect(error.fields).to eq(%i[family]) }
      expect(tag.reload.family).to eq("diet")
    end

    it "lets a restated, unchanged slug through" do
      tag = create(:tag, slug: "diet-halal")

      described_class.update!(tag, slug: "diet-halal", name: "Halal-certified")

      expect(tag.reload).to have_attributes(slug: "diet-halal", name: "Halal-certified")
    end
  end
end
