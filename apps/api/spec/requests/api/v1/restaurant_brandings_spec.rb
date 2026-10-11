require "rails_helper"
require "vips"

# The branding door is owner-or-admin: a stranger must not be able to put
# their image on someone else's restaurant, and an owner's phone photo must
# land without GPS. Replacing an image must not leave the old blob behind.
RSpec.describe "PATCH /api/v1/restaurants/:id/branding", type: :request do
  let(:owner)      { create(:user) }
  let(:restaurant) { create(:restaurant, :published, claimed_by_user: owner, claimed_at: Time.current) }

  def logo_file
    fixture_file_upload(Rails.root.join("spec/fixtures/files/clean-photo.jpg"), "image/jpeg")
  end

  def patch_branding(as:, params:)
    patch "/api/v1/restaurants/#{restaurant.slug}/branding",
          params: params, headers: as ? auth_headers_for(as) : {}
  end

  it "lets the verified owner upload a logo and a banner" do
    patch_branding(as: owner, params: { logo: logo_file, banner: logo_file })

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["logo_url"]).to be_present
    expect(response.parsed_body["banner_url"]).to be_present
    expect(response.parsed_body["slug"]).to eq(restaurant.slug)
    expect(restaurant.reload.logo).to be_attached
    expect(restaurant.banner).to be_attached
  end

  it "lets an admin brand a draft restaurant" do
    draft = create(:restaurant, status: "draft")
    patch "/api/v1/restaurants/#{draft.id}/branding",
          params: { logo: logo_file }, headers: auth_headers_for(create(:user, :admin))

    expect(response).to have_http_status(:ok)
    expect(draft.reload.logo).to be_attached
  end

  it "refuses a signed-in user who is not the owner" do
    patch_branding(as: create(:user), params: { logo: logo_file })

    expect(response).to have_http_status(:forbidden)
    expect(restaurant.reload.logo).not_to be_attached
  end

  it "refuses an unclaimed restaurant's creator, who is not its owner" do
    creator = create(:user)
    unclaimed = create(:restaurant, :published, created_by_user: creator)
    patch "/api/v1/restaurants/#{unclaimed.id}/branding",
          params: { logo: logo_file }, headers: auth_headers_for(creator)

    expect(response).to have_http_status(:forbidden)
  end

  it "requires a session" do
    patch_branding(as: nil, params: { logo: logo_file })

    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects a file that is not an image" do
    pdf = Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4"), "application/pdf", original_filename: "menu.pdf")
    patch_branding(as: owner, params: { logo: pdf })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["code"]).to eq("unsupported_type")
    expect(restaurant.reload.logo).not_to be_attached
  end

  it "strips GPS from the stored logo" do
    gps_file = JpegWithGps.tempfile
    patch_branding(as: owner, params: { logo: Rack::Test::UploadedFile.new(gps_file.path, "image/jpeg") })

    expect(response).to have_http_status(:ok)
    stored = Vips::Image.new_from_buffer(restaurant.reload.logo.download, "")
    expect(stored.get_fields.grep(/gps/i)).to be_empty
  end

  it "replaces the previous logo and purges its blob" do
    patch_branding(as: owner, params: { logo: logo_file })
    first_blob = restaurant.reload.logo.blob

    expect {
      patch_branding(as: owner, params: { logo: logo_file })
    }.to have_enqueued_job(ActiveStorage::PurgeJob).with(first_blob)
    expect(restaurant.reload.logo.blob).not_to eq(first_blob)
    expect(ActiveStorage::Attachment.where(record: restaurant, name: "logo").count).to eq(1)
  end

  it "removes an image with the flag and leaves the other alone" do
    patch_branding(as: owner, params: { logo: logo_file, banner: logo_file })

    patch_branding(as: owner, params: { remove_logo: "true" })

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["logo_url"]).to be_nil
    expect(response.parsed_body["banner_url"]).to be_present
    expect(restaurant.reload.logo).not_to be_attached
    expect(restaurant.banner).to be_attached
  end

  it "lets the remove flag win over an upload in the same request" do
    patch_branding(as: owner, params: { logo: logo_file })

    patch_branding(as: owner, params: { logo: logo_file, remove_logo: "true" })

    expect(response).to have_http_status(:ok)
    expect(restaurant.reload.logo).not_to be_attached
  end

  it "shows the logo on the public detail and list rows" do
    patch_branding(as: owner, params: { logo: logo_file, banner: logo_file })

    get "/api/v1/restaurants/#{restaurant.slug}"
    expect(response.parsed_body["logo_url"]).to be_present
    expect(response.parsed_body["banner_url"]).to be_present

    get "/api/v1/restaurants"
    row = response.parsed_body["restaurants"].find { |r| r["id"] == restaurant.id }
    expect(row["logo_url"]).to be_present
    expect(row).not_to have_key("banner_url")
  end
end
