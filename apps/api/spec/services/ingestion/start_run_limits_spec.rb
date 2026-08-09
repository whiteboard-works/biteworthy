require "rails_helper"

# The input-size caps had no spec before the super tier was added, which
# made it impossible to tell a deliberate bypass from a broken check.
# These pin all three: the ordinary cap, the raised one the super tier
# gets, and the ceiling that raised one still has.
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

      expect(start(user, files: [ big ]).error).to eq(:file_too_large)
    end

    it "refuses pasted text over the character limit" do
      text = "a" * (described_class::MAX_SOURCE_TEXT_CHARS_DEFAULT + 1)

      expect(start(user, source_text: text).error).to eq(:text_too_large)
    end
  end

  # Raised, not removed. The ceiling still exists because these caps bound
  # what gets base64-encoded into one Anthropic request, not only what it
  # costs — an unbounded payload is accepted, uploaded, and then dies on a
  # request-size 400, which is the failure the door is supposed to catch.
  describe "input caps for a super admin" do
    let(:user)  { create(:user, :super_admin) }
    let(:mult)  { described_class::SUPER_ADMIN_INPUT_MULTIPLIER }

    it "allows more files than the ordinary per-run limit" do
      files = Array.new(described_class::MAX_INPUT_FILES_DEFAULT + 1) { upload }

      expect(start(user, files: files).error).not_to eq(:too_many_files)
    end

    it "still refuses beyond the raised file-count ceiling" do
      files = Array.new((described_class::MAX_INPUT_FILES_DEFAULT * mult) + 1) { upload }

      expect(start(user, files: files).error).to eq(:too_many_files)
    end

    it "allows a file over the ordinary byte limit" do
      big = upload(bytes: described_class::MAX_INPUT_FILE_BYTES_DEFAULT + 1)

      expect(start(user, files: [ big ]).error).not_to eq(:file_too_large)
    end

    # The per-file 5× is clamped by the aggregate ceiling — a single file
    # cannot be bigger than the whole batch is allowed to be, so the
    # nominal 50 MB is really 20 MB. Pinned both ways so nobody reads the
    # multiplier as 50 MB of real headroom, and so the refusal reports the
    # limit that actually applied rather than the nominal one.
    it "clamps the per-file ceiling to the aggregate one" do
      over = upload(bytes: described_class::MAX_TOTAL_INPUT_BYTES_DEFAULT + 1)

      result = start(user, files: [ over ])

      expect(result.error).to eq(:file_too_large)
      expect(result.detail[:limit_bytes]).to eq(described_class::MAX_TOTAL_INPUT_BYTES_DEFAULT)
    end

    it "still allows a file well over the ordinary per-file cap" do
      big = upload(bytes: described_class::MAX_INPUT_FILE_BYTES_DEFAULT * 2)

      expect(start(user, files: [ big ]).error).to be_nil
    end

    it "allows pasted text over the ordinary character limit" do
      text = "a" * (described_class::MAX_SOURCE_TEXT_CHARS_DEFAULT + 1)

      expect(start(user, source_text: text).error).to be_nil
    end

    it "still refuses beyond the raised character ceiling" do
      text = "a" * ((described_class::MAX_SOURCE_TEXT_CHARS_DEFAULT * mult) + 1)

      expect(start(user, source_text: text).error).to eq(:text_too_large)
    end

    # The one check that is not a size limit stays on for everybody.
    it "still refuses a file type the extractor cannot read" do
      bad = upload(content_type: "text/csv")

      expect(start(user, files: [ bad ]).error).to eq(:unsupported_file_type)
    end
  end

  # Multiplying the count and the per-file size independently multiplies
  # their product — 5× × 5× is 25× in aggregate, which turned a 100 MB
  # ceiling into 2.5 GB. The extractor base64-encodes every blob into one
  # in-memory request, so that is gigabytes built in the worker before
  # Anthropic rejects it for exceeding the request limit.
  describe "the aggregate payload ceiling" do
    def files_totalling(bytes, count:)
      Array.new(count) { upload(bytes: bytes / count) }
    end

    it "refuses a batch of individually-legal files that is too big together" do
      user  = create(:user)
      # Five files, each under the 10 MB per-file cap, 25 MB together.
      files = files_totalling(25 * 1024 * 1024, count: 5)

      result = start(user, files: files)

      expect(result.error).to eq(:payload_too_large)
      expect(result.detail[:limit_bytes]).to eq(described_class::MAX_TOTAL_INPUT_BYTES_DEFAULT)
    end

    # Not multiplied for anybody: this ceiling is about what the API will
    # accept, not about who is paying for it — the same reasoning that
    # keeps the content-type check unskippable.
    it "binds a super admin too" do
      user  = create(:user, :super_admin)
      files = files_totalling(25 * 1024 * 1024, count: 5)

      expect(start(user, files: files).error).to eq(:payload_too_large)
    end

    it "lets a realistic multi-page menu through" do
      user  = create(:user)
      files = files_totalling(8 * 1024 * 1024, count: 6)

      expect(start(user, files: files).error).to be_nil
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
