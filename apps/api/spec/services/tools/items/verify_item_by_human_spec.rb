require "rails_helper"

RSpec.describe Tools::Items::VerifyItemByHuman, type: :tool do
  let(:user) { create(:user) }
  let(:item) { create(:item, :published) }

  def call(**args)
    described_class.call(server_context: { user_id: user.id }, **args)
  end

  def payload(response)
    response.to_h[:structuredContent]
  end

  describe ".call" do
    it "marks an item as human verified" do
      response = call(item_id: item.id)

      expect(response.to_h[:isError]).to be false
      expect(item.reload.human_verified?).to be true
      expect(item.human_verified_by_user).to eq(user)
    end

    it "returns verification information" do
      response = call(item_id: item.id)

      expect(payload(response)[:human_verified]).to be true
      expect(payload(response)[:human_verified_at]).to be_present
      expect(payload(response)[:restaurant_verified]).to be false
    end

    it "returns not found for nonexistent item" do
      response = call(item_id: SecureRandom.uuid)

      expect(response.to_h[:isError]).to be true
      expect(payload(response)[:error]).to eq("not_found")
    end

    it "is idempotent" do
      call(item_id: item.id)
      first_verified_at = item.reload.human_verified_at

      call(item_id: item.id)

      expect(item.reload.human_verified_at).to eq(first_verified_at)
      expect(item.human_verified_by_user).to eq(user)
    end
  end
end
