require "rails_helper"

RSpec.describe Tools::Items::VerifyItemByRestaurant, type: :tool do
  let(:admin) { create(:user, :admin) }
  let(:item) { create(:item, :published) }
  let(:context) { build_tool_context(user: admin) }

  describe ".perform" do
    it "requires admin" do
      user = create(:user)
      non_admin_context = build_tool_context(user: user)

      expect {
        described_class.perform(context: non_admin_context, item_id: item.id)
      }.to raise_error(Tools::Errors::Forbidden)
    end

    it "marks an item as restaurant verified" do
      result = described_class.perform(context: context, item_id: item.id)

      expect(result).to be_success
      expect(item.reload.restaurant_verified?).to be true
      expect(item.restaurant_verified_by_user).to eq(admin)
    end

    it "returns verification information" do
      result = described_class.perform(context: context, item_id: item.id)

      expect(result.data[:restaurant_verified]).to be true
      expect(result.data[:restaurant_verified_at]).to be_present
      expect(result.data[:human_verified]).to be false
    end

    it "locks item from editing by non-admins" do
      described_class.perform(context: context, item_id: item.id)

      expect(item.can_be_edited_by?(admin)).to be true
      expect(item.can_be_edited_by?(create(:user))).to be false
    end

    it "raises NotFound for nonexistent item" do
      expect {
        described_class.perform(context: context, item_id: SecureRandom.uuid)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "is idempotent" do
      described_class.perform(context: context, item_id: item.id)
      first_verified_at = item.reload.restaurant_verified_at

      travel 1.hour do
        described_class.perform(context: context, item_id: item.id)
      end

      expect(item.reload.restaurant_verified_at).to be > first_verified_at
      expect(item.restaurant_verified_by_user).to eq(admin)
    end
  end
end
