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

  # `users.email` is citext. Devise's `case_insensitive_keys` already
  # downcases on the Devise-owned paths, but `User.from_omniauth`,
  # admin creates, and seeds write the address straight through — so
  # before this, a provider returning `Foo@x.com` for someone who
  # signed up as `foo@x.com` created a SECOND account, silently
  # splitting their saved dishes and dietary profile across two logins.
  describe "email case-insensitivity" do
    let!(:existing) do
      User.create!(email: "Diner@Example.com", password: "password123",
                   password_confirmation: "password123")
    end

    it "refuses a second account differing only in case" do
      dupe = User.new(email: "diner@example.com", password: "password123",
                      password_confirmation: "password123")
      expect(dupe).not_to be_valid
      # …and the database backs the validation up, for the write paths
      # that skip validations entirely.
      expect { dupe.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "finds the account regardless of the case queried" do
      expect(User.find_by(email: "DINER@EXAMPLE.COM")).to eq(existing)
    end

    # Devise downcases on its own paths, so the row above is stored
    # lowercase and Devise alone would look sufficient. It isn't: put a
    # mixed-case address in through a path Devise doesn't own — which
    # is exactly what from_omniauth and seeds do — and only the citext
    # column stops the duplicate.
    it "still refuses the duplicate when the stored address skipped Devise" do
      existing.update_column(:email, "Diner@Example.com")

      expect {
        User.create!(email: "diner@example.com", password: "password123",
                     password_confirmation: "password123")
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
