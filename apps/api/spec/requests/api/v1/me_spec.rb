require "rails_helper"

# PATCH /api/v1/me — self-service account editing. The contract that
# matters: `handle` is the ONLY writable field. The payload rides the
# same params hash as everything else, so an unpermitted `is_admin` or
# `email` must fall on the floor rather than escalate the caller.
RSpec.describe "Me endpoint", type: :request do
  let(:user) { create(:user) }

  describe "PATCH /api/v1/me" do
    it "updates the handle, downcased, and returns the user payload" do
      patch "/api/v1/me", params: { handle: "Chosen_Name" }, headers: auth_headers_for(user)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("user", "handle")).to eq("chosen_name")
      expect(user.reload.handle).to eq("chosen_name")
    end

    it "frees the old handle for someone else" do
      old_handle = user.handle
      patch "/api/v1/me", params: { handle: "moved_on" }, headers: auth_headers_for(user)

      expect(response).to have_http_status(:ok)
      expect(User.new(handle: old_handle).tap(&:validate).errors[:handle]).to be_empty
    end

    it "422s with a per-field error when the handle is taken, any case" do
      create(:user, handle: "already_taken")

      patch "/api/v1/me", params: { handle: "Already_Taken" }, headers: auth_headers_for(user)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"]).to have_key("handle")
    end

    it "422s a malformed handle" do
      patch "/api/v1/me", params: { handle: "no spaces!" }, headers: auth_headers_for(user)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"]).to have_key("handle")
      expect(user.reload.handle).not_to eq("no spaces!")
    end

    it "ignores unpermitted fields — is_admin and email cannot ride along" do
      patch "/api/v1/me",
            params: { handle: "still_fine", is_admin: true, email: "hijack@example.com" },
            headers: auth_headers_for(user)

      expect(response).to have_http_status(:ok)
      user.reload
      expect(user.is_admin).to be false
      expect(user.email).not_to eq("hijack@example.com")
      expect(user.handle).to eq("still_fine")
    end

    it "401s without a token" do
      patch "/api/v1/me", params: { handle: "whoever" }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
