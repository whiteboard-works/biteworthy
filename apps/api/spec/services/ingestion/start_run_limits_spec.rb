require "rails_helper"

# The input-size caps had no spec before the super tier was added, which
# made it impossible to tell a deliberate bypass from a broken check.
# These pin both directions: the cap still refuses an ordinary caller,
# and it stops refusing the one account that can only be granted from a
# shell.
#
# The content-type check is in here too, and deliberately not bypassed —
# it is not a limit. A file the extractor cannot read fails inside the
# vision call, after it has been paid for, with an error about the model
# rather than about the file.
RSpec.describe Ingestion::StartRun do
  let(:city)       { create(:city, slug: "durango", name: "Durango") }
  let(:restaurant) { create(:restaurant, :published, city: city) }

  # A real blob, because the bypass path gets far enough to attach it —
  # which is the point: a cap that "passes" by failing later has not been
  # bypassed. `byte_size` is overwritten rather than actually uploading
  # 10 MB; it is the column `byte_size_of` reads.
  def upload(bytes: 1_024, content_type: "image/png")
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("x" * 16), filename: "menu.png", content_type: content_type
    )
    blob.update_column(:byte_size, bytes)
    blob.reload
  end

  def start(user, **kwargs)
    described_class.call(user: user, restaurant: restaurant, **kwargs)
  end

  describe "input caps for an ordinary caller" do
    let(:user) { create(:user) }

    it "refuses more files than the per-run limit" do
      files = Array.new(described_class::MAX_INPUT_FILES_DEFAULT + 1) { upload }

      expect(start(user, files: files).error).to eq(:too_many_files)
    end

    it "refuses a file over the byte limit" do
      big = upload(bytes: described_class::MAX_INPUT_FILE_BYTES_DEFAULT + 1)

      expect(start(user, files: [big]).error).to eq(:file_too_large)
    end

    it "refuses pasted text over the character limit" do
      text = "a" * (described_class::MAX_SOURCE_TEXT_CHARS_DEFAULT + 1)

      expect(start(user, source_text: text).error).to eq(:text_too_large)
    end
  end

  describe "input caps for a super admin" do
    let(:user) { create(:user, :super_admin) }

    it "allows more files than the per-run limit" do
      files = Array.new(described_class::MAX_INPUT_FILES_DEFAULT + 1) { upload }

      expect(start(user, files: files).error).not_to eq(:too_many_files)
    end

    it "allows a file over the byte limit" do
      big = upload(bytes: described_class::MAX_INPUT_FILE_BYTES_DEFAULT + 1)

      expect(start(user, files: [big]).error).not_to eq(:file_too_large)
    end

    it "allows pasted text over the character limit" do
      text = "a" * (described_class::MAX_SOURCE_TEXT_CHARS_DEFAULT + 1)

      expect(start(user, source_text: text).error).to be_nil
    end

    # The one check that is not a size limit stays on for everybody.
    it "still refuses a file type the extractor cannot read" do
      bad = upload(content_type: "text/csv")

      expect(start(user, files: [bad]).error).to eq(:unsupported_file_type)
    end
  end

  # Already true before the super tier (super admin implies admin), but
  # worth pinning next to the caps it does *not* cover — the asymmetry is
  # the thing a future reader will otherwise assume is a mistake.
  describe "quota and spend ceiling" do
    it "refuses an ordinary caller who is over the daily run quota" do
      user = create(:user)
      described_class::PER_USER_DAILY_RUNS_DEFAULT.times do
        create(:ingestion_run, user: user, restaurant: restaurant)
      end

      expect(start(user, source_text: "Tacos $3").error).to eq(:quota_exceeded)
    end

    it "lets a super admin past it" do
      user = create(:user, :super_admin)
      described_class::PER_USER_DAILY_RUNS_DEFAULT.times do
        create(:ingestion_run, user: user, restaurant: restaurant)
      end

      expect(start(user, source_text: "Tacos $3").error).to be_nil
    end
  end
end
