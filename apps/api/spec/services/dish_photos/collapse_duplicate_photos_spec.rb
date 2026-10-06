require "rails_helper"

RSpec.describe DishPhotos::CollapseDuplicatePhotos do
  let(:item) { create(:item, :published) }
  let(:credited) { create(:dish_photo_submission, :approved, item: item, credit_name: "Pat") }
  let(:other) { create(:dish_photo_submission, :approved, item: item, credit_name: "Other") }

  def extra_attachment!(blob_source)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(blob_source.photo.download),
      filename: "extra.jpg",
      content_type: "image/jpeg"
    )
    ActiveStorage::Attachment.create!(record: item, name: "photo", blob: blob)
    blob
  end

  def photo_blob_ids
    ActiveStorage::Attachment.where(record: item, name: "photo").pluck(:blob_id)
  end

  it "keeps the attachment matching the credited submission and purges the rest" do
    item.update!(photo_submission_id: credited.id)
    item.photo.attach(
      io: StringIO.new(credited.photo.download),
      filename: "credited.jpg",
      content_type: "image/jpeg"
    )
    extra_attachment!(other)

    expect(photo_blob_ids.size).to eq(2)

    result = described_class.call(dry_run: false)

    expect(result[:items_collapsed]).to eq(1)
    expect(photo_blob_ids.size).to eq(1)
    expect(item.reload.photo.blob.checksum).to eq(credited.photo.blob.checksum)
  end

  it "is a no-op on dry run, then idempotent once applied" do
    item.update!(photo_submission_id: credited.id)
    item.photo.attach(
      io: StringIO.new(credited.photo.download),
      filename: "credited.jpg",
      content_type: "image/jpeg"
    )
    extra_attachment!(other)

    dry = described_class.call(dry_run: true)
    expect(dry[:dry_run]).to be(true)
    expect(dry[:items_collapsed]).to eq(1)
    expect(photo_blob_ids.size).to eq(2)

    described_class.call(dry_run: false)
    again = described_class.call(dry_run: false)
    expect(again[:items_examined]).to eq(0)
    expect(again[:items_collapsed]).to eq(0)
    expect(photo_blob_ids.size).to eq(1)
  end

  it "falls back to the newest attachment when no credit matches" do
    older = extra_attachment!(credited)
    newer = extra_attachment!(other)
    ActiveStorage::Attachment.find_by!(blob_id: older.id).update_column(:created_at, 2.minutes.ago)
    ActiveStorage::Attachment.find_by!(blob_id: newer.id).update_column(:created_at, Time.current)
    item.update!(photo_submission_id: nil)

    described_class.call(dry_run: false)

    expect(photo_blob_ids).to eq([ newer.id ])
  end
end
