require "rails_helper"

# Two approve-and-sets on the same dish must not both attach. has_one
# attached :photo will INSERT two rows unless the item row is locked, and
# a later staff PATCH only purges one — leaving an uncredited diner photo
# on the dish. Transactional fixtures hide that, so this uses real
# connections the same way Cities::Create's race spec does.
RSpec.describe "DishPhotos::Moderate concurrent approve-and-set" do
  self.use_transactional_tests = false

  after { wipe_committed_rows! }

  it "leaves exactly one item photo whose checksum matches the credited diner" do
    admin = create(:user, :admin)
    diner_a = create(:user, display_name: "Diner A")
    diner_b = create(:user, display_name: "Diner B")
    item = create(:item, :published)
    submission_a = create(:dish_photo_submission, item: item, user: diner_a, credit_name: "Diner A")
    submission_b = create(:dish_photo_submission, item: item, user: diner_b, credit_name: "Diner B")
    replace_photo!(submission_b, Rails.root.join("spec/fixtures/files/test-image.jpg"))

    arrived = 0
    mutex = Mutex.new
    outcomes = [ submission_a, submission_b ].map do |submission|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          mutex.synchronize { arrived += 1 }
          deadline = Time.current + 1
          sleep 0.01 while mutex.synchronize { arrived } < 2 && Time.current < deadline
          DishPhotos::Moderate.new(submission, reviewer: admin).approve!(replace_item_photo: true)
          :approved
        rescue DishPhotos::Moderate::NotPending
          :not_pending
        end
      end
    end.map(&:value)

    expect(outcomes).to all(eq(:approved).or(eq(:not_pending)))

    item.reload
    attachments = ActiveStorage::Attachment.where(record: item, name: "photo")
    expect(attachments.count).to eq(1)
    expect(item.photo_submission_id).to be_present

    winner = DishPhotoSubmission.find(item.photo_submission_id)
    expect(winner).to be_approved
    expect(item.photo.blob.checksum).to eq(winner.photo.blob.checksum)
    expect(winner.credit_name).to eq(item.photo_submission.credit_name)
  end

  def replace_photo!(record, path)
    record.photo.purge
    record.photo.attach(
      io: File.open(path),
      filename: File.basename(path),
      content_type: "image/jpeg"
    )
  end

  def wipe_committed_rows!
    Item.update_all(photo_submission_id: nil)
    ActiveStorage::VariantRecord.delete_all
    ActiveStorage::Attachment.delete_all
    DishPhotoSubmission.delete_all
    ItemIngredient.delete_all
    ItemTag.delete_all
    ItemVariant.delete_all
    ItemModifier.delete_all
    Item.delete_all
    MenuSection.delete_all
    Menu.delete_all
    Address.delete_all
    Restaurant.delete_all
    UserProfile.delete_all
    User.delete_all
    City.delete_all
    ActiveStorage::Blob.delete_all
  end
end
