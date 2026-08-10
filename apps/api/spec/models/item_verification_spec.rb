require "rails_helper"

RSpec.describe Item, type: :model, focus: :item_verification do
  describe "verification methods" do
    let(:item) { create(:item, :published) }
    let(:user) { create(:user) }

    describe "#human_verified?" do
      it "returns false when not verified" do
        expect(item.human_verified?).to be false
      end

      it "returns true when human_verified_at is set" do
        item.update!(human_verified_at: Time.current)
        expect(item.human_verified?).to be true
      end
    end

    describe "#restaurant_verified?" do
      it "returns false when not verified" do
        expect(item.restaurant_verified?).to be false
      end

      it "returns true when restaurant_verified_at is set" do
        item.update!(restaurant_verified_at: Time.current)
        expect(item.restaurant_verified?).to be true
      end
    end

    describe "#mark_human_verified!" do
      it "sets human_verified_at and human_verified_by_user" do
        item.mark_human_verified!(user)
        item.reload
        expect(item.human_verified_at).to be_present
        expect(item.human_verified_by_user).to eq(user)
      end

      it "is idempotent" do
        first_time = Time.current
        item.mark_human_verified!(user)
        first_id = item.reload.human_verified_by_user_id

        travel 1.hour do
          item.mark_human_verified!(user)
        end

        expect(item.reload.human_verified_by_user_id).to eq(first_id)
        expect(item.human_verified_at).to be > first_time
      end
    end

    describe "#mark_restaurant_verified!" do
      it "sets restaurant_verified_at and restaurant_verified_by_user" do
        item.mark_restaurant_verified!(user)
        item.reload
        expect(item.restaurant_verified_at).to be_present
        expect(item.restaurant_verified_by_user).to eq(user)
      end

      it "locks the item from editing by others" do
        admin = create(:user, :admin)
        item.mark_restaurant_verified!(user)
        expect(item.can_be_edited_by?(admin)).to be true
        expect(item.can_be_edited_by?(create(:user))).to be false
      end
    end

    describe "#can_be_edited_by?" do
      context "when not restaurant verified" do
        it "allows any admin to edit" do
          admin = create(:user, :admin)
          expect(item.can_be_edited_by?(admin)).to be true
        end

        it "allows any regular user to edit (before restaurant verification)" do
          user = create(:user)
          expect(item.can_be_edited_by?(user)).to be true
        end
      end

      context "when restaurant verified" do
        before { item.mark_restaurant_verified!(user) }

        it "allows super admin to edit" do
          admin = create(:user, :admin)
          expect(item.can_be_edited_by?(admin)).to be true
        end

        it "allows the verifying user to edit" do
          expect(item.can_be_edited_by?(user)).to be true
        end

        it "denies other users from editing" do
          other_user = create(:user)
          expect(item.can_be_edited_by?(other_user)).to be false
        end

        it "denies nil user from editing" do
          expect(item.can_be_edited_by?(nil)).to be false
        end
      end
    end
  end
end
