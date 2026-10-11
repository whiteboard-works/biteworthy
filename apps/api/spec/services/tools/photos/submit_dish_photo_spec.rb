require "rails_helper"
require "vips"

# The chat door to the diner dish-photo queue. What it must get right on
# its own: the user — not the model — attests to owning the photo, an
# attachment only resolves for the account that uploaded it, and nothing
# reaches the dish until a moderator approves it.
RSpec.describe Tools::Photos::SubmitDishPhoto do
  let(:diner)      { create(:user, display_name: "Pat Diner") }
  let(:restaurant) { create(:restaurant, :published) }
  let(:item)       { create(:item, :published, restaurant:) }

  def upload_for(user, io: File.open(Rails.root.join("spec/fixtures/files/clean-photo.jpg")))
    ActiveStorage::Blob.create_and_upload!(
      io:, filename: "dish.jpg", content_type: "image/jpeg",
      metadata: { "uploaded_by_user_id" => user.id }
    )
  end

  def payload(response) = response.to_h[:structuredContent]

  def call(as:, confirmation: nil, **args)
    described_class.call(
      server_context: { user_id: as.id, public_host: "https://biteworthy.test" },
      confirmation:, **args
    )
  end

  # What the person agreed to, minted the way the chat does on approve.
  def confirmed_call(as:, **args)
    token = Tools::Confirmation.mint(tool: described_class.name_value, args:, user_id: as.id)
    call(as:, confirmation: token, **args)
  end

  it "asks the user to attest before anything is queued" do
    response = call(as: diner, item_id: item.id, attachment_id: upload_for(diner).signed_id)

    expect(payload(response)[:error]).to eq("confirmation_required")
    expect(payload(response)[:prompt]).to include(item.name, "took this photo")
    expect(DishPhotoSubmission.count).to eq(0)
  end

  # In accept_edits the chat runs anything recoverable on a standing yes.
  # An ownership attestation is not an edit someone agreed to in advance.
  it "parks even under the accept_edits standing grant" do
    expect(Chat::ModePolicy.new("accept_edits").decide(described_class, {})).to eq(:park)
  end

  it "queues a pending submission once confirmed, leaving the dish alone" do
    response = confirmed_call(as: diner, item_id: item.id, attachment_id: upload_for(diner).signed_id)

    submission = DishPhotoSubmission.sole
    expect(payload(response)[:submission]).to include(id: submission.id, status: "pending")
    expect(submission).to have_attributes(user: diner, item:, owns_rights: true, credit_name: "Pat Diner")
    expect(item.reload.photo).not_to be_attached
  end

  it "strips GPS from the stored copy" do
    gps = JpegWithGps.tempfile
    confirmed_call(as: diner, item_id: item.id, attachment_id: upload_for(diner, io: gps).signed_id)

    stored = Vips::Image.new_from_buffer(DishPhotoSubmission.sole.photo.download, "")
    expect(stored.get_fields.grep(/gps/i)).to be_empty
  ensure
    gps&.close!
  end

  # A grant is reusable for its whole TTL, so the gated call must be
  # idempotent: the same yes replayed must not queue the photo twice.
  it "returns the existing submission when the same confirmed call is replayed" do
    args = { item_id: item.id, attachment_id: upload_for(diner).signed_id }

    first  = payload(confirmed_call(as: diner, **args))
    second = payload(confirmed_call(as: diner, **args))

    expect(second[:submission][:id]).to eq(first[:submission][:id])
    expect(DishPhotoSubmission.count).to eq(1)
  end

  # A stale yes must not bring back a photo the user took back.
  it "does not requeue a withdrawn photo when the confirmed call is replayed" do
    args = { item_id: item.id, attachment_id: upload_for(diner).signed_id }
    confirmed_call(as: diner, **args)
    DishPhotoSubmission.sole.withdraw!

    response = confirmed_call(as: diner, **args)

    expect(payload(response)[:submission][:status]).to eq("withdrawn")
    expect(DishPhotoSubmission.count).to eq(1)
  end

  it "does not resolve an attachment somebody else uploaded" do
    response = confirmed_call(as: diner, item_id: item.id, attachment_id: upload_for(create(:user)).signed_id)

    expect(payload(response)[:error]).to eq("invalid_argument")
    expect(DishPhotoSubmission.count).to eq(0)
  end

  it "refuses a dish that is not published" do
    draft = create(:item, restaurant:)
    response = confirmed_call(as: diner, item_id: draft.id, attachment_id: upload_for(diner).signed_id)

    expect(payload(response)[:error]).to eq("not_found")
  end

  it "passes the per-dish pending limit through as a readable refusal" do
    DishPhotoSubmission::PENDING_PER_ITEM_LIMIT.times do
      confirmed_call(as: diner, item_id: item.id, attachment_id: upload_for(diner).signed_id)
    end

    response = confirmed_call(as: diner, item_id: item.id, attachment_id: upload_for(diner).signed_id)

    expect(payload(response)[:error]).to eq("pending_limit")
    expect(payload(response)[:message]).to match(/waiting on a moderator/)
  end

  it "is not offered to an anonymous caller" do
    expect(Tools::Registry.for(Tools::Context.new({})).map(&:name_value)).not_to include("submit_dish_photo")
  end
end
