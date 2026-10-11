require "rails_helper"
require "vips"

# The direct door: the restaurant's verified owner or an admin puts a
# photo on a dish with no moderation step. What it must get right: who,
# that the stored copy has no GPS, and that it replaces rather than
# stacks a photo.
RSpec.describe Tools::Photos::SetItemPhoto do
  let(:owner)      { create(:user) }
  let(:restaurant) { create(:restaurant, :published, claimed_by_user: owner, claimed_at: Time.current) }
  let(:item)       { create(:item, :published, restaurant:) }

  def upload_for(user, io: File.open(Rails.root.join("spec/fixtures/files/clean-photo.jpg")))
    ActiveStorage::Blob.create_and_upload!(
      io:, filename: "dish.jpg", content_type: "image/jpeg",
      metadata: { "uploaded_by_user_id" => user.id }
    )
  end

  def payload(response) = response.to_h[:structuredContent]

  def call(as:, **args)
    described_class.call(server_context: { user_id: as.id, public_host: "https://biteworthy.test" }, **args)
  end

  it "puts the owner's photo on the dish without GPS" do
    gps = JpegWithGps.tempfile
    response = call(as: owner, item_id: item.id, attachment_id: upload_for(owner, io: gps).signed_id)

    expect(payload(response)[:photo_url]).to be_present
    stored = Vips::Image.new_from_buffer(item.reload.photo.download, "")
    expect(stored.get_fields.grep(/gps/i)).to be_empty
  ensure
    gps&.close!
  end

  it "lets an admin set it on a restaurant nobody has claimed" do
    admin = create(:user, :admin)
    unclaimed = create(:item, :published, restaurant: create(:restaurant, :published))

    call(as: admin, item_id: unclaimed.id, attachment_id: upload_for(admin).signed_id)

    expect(unclaimed.reload.photo).to be_attached
  end

  it "replaces the current photo and drops the diner credit that came with it" do
    submission = create(:dish_photo_submission, item:, status: "approved")
    item.photo.attach(io: File.open(Rails.root.join("spec/fixtures/files/test-image.jpg")),
                      filename: "old.jpg", content_type: "image/jpeg")
    item.update!(photo_submission: submission)
    old_blob_id = item.photo.blob.id

    call(as: owner, item_id: item.id, attachment_id: upload_for(owner).signed_id)

    item.reload
    expect(item.photo.blob.id).not_to eq(old_blob_id)
    expect(ActiveStorage::Attachment.where(record: item, name: "photo").count).to eq(1)
    expect(item.photo_submission_id).to be_nil
  end

  it "refuses a diner who is not the verified owner" do
    stranger = create(:user)
    response = call(as: stranger, item_id: item.id, attachment_id: upload_for(stranger).signed_id)

    expect(payload(response)[:error]).to eq("forbidden")
    expect(payload(response)[:message]).to include("submit_dish_photo")
    expect(item.reload.photo).not_to be_attached
  end

  it "does not resolve an attachment somebody else uploaded" do
    response = call(as: owner, item_id: item.id, attachment_id: upload_for(create(:user)).signed_id)

    expect(payload(response)[:error]).to eq("invalid_argument")
    expect(item.reload.photo).not_to be_attached
  end

  # Same reach as get_menu and submit_dish_photo: the card promises the
  # photo shows to everyone, which is only true of a live dish.
  it "refuses a dish that is not published" do
    draft = create(:item, restaurant:)
    response = call(as: owner, item_id: draft.id, attachment_id: upload_for(owner).signed_id)

    expect(payload(response)[:error]).to eq("not_found")
    expect(draft.reload.photo).not_to be_attached
  end

  it "refuses a PDF" do
    pdf = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4\n%%EOF"), filename: "menu.pdf", content_type: "application/pdf",
      metadata: { "uploaded_by_user_id" => owner.id }
    )

    response = call(as: owner, item_id: item.id, attachment_id: pdf.signed_id)

    expect(payload(response)[:error]).to eq("unsupported_type")
  end

  # Replacing a photo purges the old one, which no later call puts back.
  it "stops for a human even under accept_edits when a photo would be replaced" do
    item.photo.attach(io: File.open(Rails.root.join("spec/fixtures/files/test-image.jpg")),
                      filename: "old.jpg", content_type: "image/jpeg")
    policy = Chat::ModePolicy.new("accept_edits")

    expect(policy.decide(described_class, { item_id: item.id })).to eq(:park)
    expect(policy.decide(described_class, { item_id: create(:item, restaurant:).id })).to eq(:run)
  end
end
