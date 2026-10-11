require "rails_helper"

RSpec.describe Tools::Items::VerifyItemByRestaurant, type: :tool do
  let(:admin) { create(:user, :admin) }
  let(:item) { create(:item, :published) }

  def call(**args)
    described_class.call(server_context: { user_id: admin.id }, **args)
  end

  def call_as(user, **args)
    described_class.call(server_context: { user_id: user.id }, **args)
  end

  def payload(response)
    response.to_h[:structuredContent]
  end

  describe ".call" do
    it "requires admin" do
      user = create(:user)
      response = call_as(user, item_id: item.id)

      expect(response.to_h[:isError]).to be true
      expect(payload(response)[:error]).to eq("forbidden")
    end

    it "marks an item as restaurant verified" do
      response = call(item_id: item.id)

      expect(item.reload.restaurant_verified?).to be true
      expect(item.restaurant_verified_by_user).to eq(admin)
      expect(payload(response)[:restaurant_verified]).to be true
    end

    it "returns verification information" do
      response = call(item_id: item.id)

      expect(payload(response)[:restaurant_verified]).to be true
      expect(payload(response)[:restaurant_verified_at]).to be_present
      expect(payload(response)[:human_verified]).to be false
    end

    it "locks item from editing by non-admins" do
      call(item_id: item.id)

      expect(item.reload.can_be_edited_by?(admin)).to be true
      expect(item.can_be_edited_by?(create(:user))).to be false
    end

    it "returns not found for nonexistent item" do
      response = call(item_id: SecureRandom.uuid)

      expect(response.to_h[:isError]).to be true
      expect(payload(response)[:error]).to eq("not_found")
    end

    it "is idempotent" do
      call(item_id: item.id)
      first_verified_at = item.reload.restaurant_verified_at

      call(item_id: item.id)

      expect(item.reload.restaurant_verified_at).to eq(first_verified_at)
      expect(item.restaurant_verified_by_user).to eq(admin)
    end
  end
end
