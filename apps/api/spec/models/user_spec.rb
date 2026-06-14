require "rails_helper"

RSpec.describe User do
  describe "#assign_default_handle (legal E9)" do
    it "keeps a handle the user chose" do
      user = User.create!(
        email: "chooser@example.com", password: "password123",
        password_confirmation: "password123", handle: "picky_eater"
      )
      expect(user.handle).to eq("picky_eater")
    end

    it "assigns a neutral default that does NOT leak the email local-part" do
      user = User.create!(
        email: "jane.doe.celiac@example.com", password: "password123",
        password_confirmation: "password123"
      )
      expect(user.handle).to match(/\Adiner_[0-9a-f]{8}\z/)
      # The old behavior derived the handle from the email — make sure
      # nothing of the local-part survives in the public handle.
      expect(user.handle).not_to include("jane")
      expect(user.handle).not_to include("doe")
      expect(user.handle).not_to include("celiac")
    end

    it "produces distinct defaults for different accounts" do
      a = User.create!(email: "a@example.com", password: "password123", password_confirmation: "password123")
      b = User.create!(email: "b@example.com", password: "password123", password_confirmation: "password123")
      expect(a.handle).not_to eq(b.handle)
    end
  end
end
