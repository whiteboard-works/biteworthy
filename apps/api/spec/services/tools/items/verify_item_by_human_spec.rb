require "rails_helper"

RSpec.describe Tools::Items::VerifyItemByHuman, type: :tool do
  let(:user) { create(:user) }
  let(:item) { create(:item, :published) }
  let(:context) { build_tool_context(user: user) }

  describe ".perform" do
    it "marks an item as human verified" do
      result = described_class.perform(context: context, item_id: item.id)

      expect(result).to be_success
      expect(item.reload.human_verified?).to be true
      expect(item.human_verified_by_user).to eq(user)
    end

    it "returns verification information" do
      result = described_class.perform(context: context, item_id: item.id)

      expect(result.data[:human_verified]).to be true
      expect(result.data[:human_verified_at]).to be_present
      expect(result.data[:restaurant_verified]).to be false
    end

    it "raises NotFound for nonexistent item" do
      expect {
        described_class.perform(context: context, item_id: SecureRandom.uuid)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "is idempotent" do
      described_class.perform(context: context, item_id: item.id)
      first_verified_at = item.reload.human_verified_at

      travel 1.hour do
        described_class.perform(context: context, item_id: item.id)
      end

      expect(item.reload.human_verified_at).to be > first_verified_at
      expect(item.human_verified_by_user).to eq(user)
    end
  end
end
