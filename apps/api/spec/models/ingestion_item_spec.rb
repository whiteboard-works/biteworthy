require "rails_helper"

RSpec.describe IngestionItem, type: :model do
  describe "#promote!" do
    let(:restaurant) { create(:restaurant, :published) }
    let(:run)        { create(:ingestion_run, restaurant: restaurant, status: "staged") }

    let!(:beef)         { create(:ingredient, slug: "meat-beef") }
    let!(:onion)        { create(:ingredient, slug: "vegetable-onion") }
    let!(:cilantro)     { create(:ingredient, slug: "herb-cilantro") }
    let!(:mexican_tag)  { create(:tag, slug: "cuisine-mexican") }

    let(:item) do
      create(:ingestion_item,
             ingestion_run: run, name: "Carne Asada Taco",
             description: "Grilled steak, cilantro, onion, lime.")
    end

    it "creates a real Item with status=published, confidence=confirmed" do
      promoted = item.promote!

      expect(promoted).to be_a(Item)
      expect(promoted.restaurant).to eq(restaurant)
      expect(promoted.name).to       eq("Carne Asada Taco")
      expect(promoted.status).to     eq("published")
      expect(promoted.confidence).to eq("confirmed")
    end

    it "creates ItemIngredient rows for every resolvable slug in ingredients_payload" do
      promoted = item.promote!

      expect(promoted.ingredients).to contain_exactly(beef, onion, cilantro)
      expect(promoted.item_ingredients.pluck(:confidence).uniq).to eq(["confirmed"])
      expect(promoted.item_ingredients.pluck(:source).uniq).to eq(["human"])
    end

    it "creates ItemTag rows from tags_payload" do
      promoted = item.promote!

      expect(promoted.tags).to contain_exactly(mexican_tag)
      expect(promoted.item_tags.first.source).to eq("human")
    end

    it "skips payload entries whose slug doesn't match the catalog (no-op)" do
      item.update!(
        ingredients_payload: [
          { "slug" => "meat-beef",       "confidence" => 0.97 },
          { "slug" => "vegetable-bigfoot", "confidence" => 0.01 } # not in catalog
        ]
      )

      promoted = item.promote!

      expect(promoted.ingredients).to contain_exactly(beef)
    end

    it "marks the IngestionItem accepted + records decided_at + links to item" do
      promoted = item.promote!

      item.reload
      expect(item.decision).to    eq("accepted")
      expect(item.item).to        eq(promoted)
      expect(item.decided_at).to  be_within(5.seconds).of(Time.current)
    end

    it "is idempotent — re-calling returns the existing Item without dup join rows" do
      first  = item.promote!
      second = item.promote!

      expect(second).to eq(first)
      expect(first.item_ingredients.count).to eq(3)
      expect(first.item_tags.count).to        eq(1)
    end

    it "raises if the IngestionRun has no restaurant" do
      orphan_run  = create(:ingestion_run, restaurant: nil)
      orphan_item = create(:ingestion_item, ingestion_run: orphan_run)

      expect { orphan_item.promote! }.to raise_error(/no restaurant/)
    end

    # Phase 4.11.3 — when Anthropic vision marked a per-dish photo on
    # the source page (image_bbox jsonb populated by 4.11.2), promote!
    # crops it out and attaches it to the new Item. Must be best-effort
    # so a single bad bbox doesn't block the whole verify queue.
    describe "dish photo attachment" do
      let(:menu_path) { Rails.root.join("spec/fixtures/menus/sample.jpg") }

      before do
        run.inputs.attach(
          io:           File.open(menu_path, "rb"),
          filename:     "menu.jpg",
          content_type: "image/jpeg"
        )
      end

      it "attaches a cropped photo when image_bbox is present" do
        item.update!(image_bbox: { "x" => 0.4, "y" => 0.4, "w" => 0.2, "h" => 0.2 })

        promoted = item.promote!

        expect(promoted.photo).to be_attached
        expect(promoted.photo.content_type).to eq("image/jpeg")
        expect(promoted.photo.byte_size).to be > 0
      end

      it "leaves photo unattached when image_bbox is nil" do
        promoted = item.promote!
        expect(promoted.photo).not_to be_attached
      end

      it "swallows cropper errors so promotion still succeeds" do
        # Bad bbox (x out of range) makes DishPhotoCropper raise. The
        # rescue must keep promotion succeeding without an attachment.
        item.update!(image_bbox: { "x" => 1.5, "y" => 0.1, "w" => 0.1, "h" => 0.1 })

        expect(Rails.logger).to receive(:warn).with(/InvalidBboxError/)
        expect { item.promote! }.not_to raise_error
        expect(item.reload.item.photo).not_to be_attached
        expect(item.decision).to eq("accepted")
      end

      it "leaves photo unattached when the run has no source blob" do
        # Edge case: bbox set but inputs purged (operator cleanup, etc.).
        # Should silently skip rather than blow up.
        run.inputs.purge
        item.update!(image_bbox: { "x" => 0.4, "y" => 0.4, "w" => 0.2, "h" => 0.2 })

        promoted = item.promote!
        expect(promoted.photo).not_to be_attached
      end
    end
  end
end
