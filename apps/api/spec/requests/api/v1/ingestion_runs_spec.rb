require "rails_helper"

RSpec.describe "Ingestion runs API", type: :request do
  let(:restaurant) { create(:restaurant, :published) }
  let(:admin)      { create(:user, password: "password123", is_admin: true) }
  let(:non_admin)  { create(:user, password: "password123", is_admin: false) }

  def auth_for(user)
    token, _ = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
    { "Authorization" => "Bearer #{token}" }
  end

  def fake_image(name = "page1.jpg")
    Rack::Test::UploadedFile.new(
      StringIO.new("\xFF\xD8\xFF\xE0".b),
      "image/jpeg",
      original_filename: name
    )
  end

  describe "POST /api/v1/ingestion_runs" do
    it "creates a run, attaches inputs, transitions to :extracting, and 201s" do
      # Stub the ExtractMenuJob so we don't try to call Anthropic.
      allow(ExtractMenuJob).to receive(:perform_later)

      expect {
        post "/api/v1/ingestion_runs",
             params: { restaurant_id: restaurant.id, inputs: [fake_image("p1.jpg"), fake_image("p2.jpg")] },
             headers: auth_for(admin)
      }.to change(IngestionRun, :count).by(1)

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body).to include("status" => "extracting", "input_kind" => "photo", "input_count" => 2)
      expect(ExtractMenuJob).to have_received(:perform_later).with(IngestionRun.last.id)
    end

    it "rejects an unauthenticated caller with 401" do
      post "/api/v1/ingestion_runs",
           params: { restaurant_id: restaurant.id, inputs: [fake_image] }

      expect(response).to have_http_status(:unauthorized)
    end

    it "creates a run for a non-admin caller (Phase 6.1 — anyone can scan)" do
      allow(ExtractMenuJob).to receive(:perform_later)

      expect {
        post "/api/v1/ingestion_runs",
             params: { restaurant_id: restaurant.id, inputs: [fake_image] },
             headers: auth_for(non_admin)
      }.to change(IngestionRun, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(IngestionRun.last.user_id).to eq(non_admin.id)
    end

    it "422s when no inputs are attached" do
      post "/api/v1/ingestion_runs",
           params: { restaurant_id: restaurant.id },
           headers: auth_for(admin)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("no_inputs")
    end

    it "404s on an unknown restaurant" do
      post "/api/v1/ingestion_runs",
           params: { restaurant_id: "00000000-0000-0000-0000-000000000000", inputs: [fake_image] },
           headers: auth_for(admin)

      expect(response).to have_http_status(:not_found)
    end

    it "auto-detects pdf input_kind from content_type" do
      allow(ExtractMenuJob).to receive(:perform_later)
      pdf = Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4"), "application/pdf",
                                         original_filename: "menu.pdf")

      post "/api/v1/ingestion_runs",
           params: { restaurant_id: restaurant.id, inputs: [pdf] },
           headers: auth_for(admin)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["input_kind"]).to eq("pdf")
    end

    context "with source_url (Phase 2.8)" do
      let(:menu_url) { "https://durango-restaurants.example/cream-bean-berry/menu" }

      before do
        # UrlFetcher's SSRF guard (#223) resolves DNS before fetching;
        # WebMock only intercepts the HTTP layer. Resolve the spec host
        # to a public address so the guard passes.
        allow(Resolv).to receive(:getaddresses)
          .with("durango-restaurants.example").and_return(["93.184.215.14"])
      end

      it "fetches the URL, attaches the response, and 201s with input_kind=url for HTML" do
        allow(ExtractMenuJob).to receive(:perform_later)
        stub_request(:get, menu_url).to_return(
          status: 200,
          body: "<html>menu html</html>",
          headers: { "Content-Type" => "text/html" }
        )

        expect {
          post "/api/v1/ingestion_runs",
               params: { restaurant_id: restaurant.id, source_url: menu_url },
               headers: auth_for(admin)
        }.to change(IngestionRun, :count).by(1)

        expect(response).to have_http_status(:created)
        body = response.parsed_body
        expect(body["input_kind"]).to    eq("url")
        expect(body["input_count"]).to   eq(1)

        run = IngestionRun.last
        expect(run.source_url).to eq(menu_url)
        expect(run.inputs).to be_attached
      end

      it "uses input_kind=pdf when the URL serves a PDF" do
        allow(ExtractMenuJob).to receive(:perform_later)
        stub_request(:get, "#{menu_url}.pdf").to_return(
          status: 200,
          body: "%PDF-1.4 fake",
          headers: { "Content-Type" => "application/pdf" }
        )

        post "/api/v1/ingestion_runs",
             params: { restaurant_id: restaurant.id, source_url: "#{menu_url}.pdf" },
             headers: auth_for(admin)

        expect(response).to have_http_status(:created)
        expect(response.parsed_body["input_kind"]).to eq("pdf")
      end

      it "422s when the upstream URL returns non-2xx" do
        stub_request(:get, menu_url).to_return(status: 503)

        post "/api/v1/ingestion_runs",
             params: { restaurant_id: restaurant.id, source_url: menu_url },
             headers: auth_for(admin)

        expect(response).to have_http_status(:unprocessable_entity)
        body = response.parsed_body
        expect(body["error"]).to  eq("url_fetch_failed")
        expect(body["reason"]).to eq("non_2xx")
        expect(body["status"]).to eq(503)
      end
    end
  end

  describe "restaurant targeting (Phase 6.2)" do
    before { allow(ExtractMenuJob).to receive(:perform_later) }

    it "lets a non-admin scan a draft restaurant they created" do
      own_draft = create(:restaurant, status: "draft", created_by_user: non_admin)

      post "/api/v1/ingestion_runs",
           params: { restaurant_id: own_draft.id, inputs: [fake_image] },
           headers: auth_for(non_admin)

      expect(response).to have_http_status(:created)
    end

    it "403s a non-admin scanning another user's draft" do
      stranger_draft = create(:restaurant, status: "draft",
                                           created_by_user: create(:user, password: "password123"))

      expect {
        post "/api/v1/ingestion_runs",
             params: { restaurant_id: stranger_draft.id, inputs: [fake_image] },
             headers: auth_for(non_admin)
      }.not_to change(IngestionRun, :count)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to eq("forbidden_restaurant")
    end

    it "lets an admin scan any draft" do
      stranger_draft = create(:restaurant, status: "draft",
                                           created_by_user: create(:user, password: "password123"))

      post "/api/v1/ingestion_runs",
           params: { restaurant_id: stranger_draft.id, inputs: [fake_image] },
           headers: auth_for(admin)

      expect(response).to have_http_status(:created)
    end
  end

  describe "community limits (Phase 6.1)" do
    before { allow(ExtractMenuJob).to receive(:perform_later) }

    around do |example|
      old_quota   = ENV["INGESTION_RUNS_PER_USER_PER_DAY"]
      old_ceiling = ENV["INGESTION_DAILY_COST_CEILING_CENTS"]
      old_files   = ENV["INGESTION_MAX_INPUT_FILES"]
      old_bytes   = ENV["INGESTION_MAX_INPUT_FILE_BYTES"]
      example.run
    ensure
      ENV["INGESTION_RUNS_PER_USER_PER_DAY"]    = old_quota
      ENV["INGESTION_DAILY_COST_CEILING_CENTS"] = old_ceiling
      ENV["INGESTION_MAX_INPUT_FILES"]          = old_files
      ENV["INGESTION_MAX_INPUT_FILE_BYTES"]     = old_bytes
    end

    describe "upload caps (Phase 6.1.1)" do
      it "422s when more files than the cap are attached" do
        ENV["INGESTION_MAX_INPUT_FILES"] = "2"

        post "/api/v1/ingestion_runs",
             params: { restaurant_id: restaurant.id,
                       inputs: [fake_image("1.jpg"), fake_image("2.jpg"), fake_image("3.jpg")] },
             headers: auth_for(non_admin)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to include("error" => "too_many_files", "limit" => 2)
      end

      it "422s when a file exceeds the byte cap" do
        ENV["INGESTION_MAX_INPUT_FILE_BYTES"] = "2"

        post "/api/v1/ingestion_runs",
             params: { restaurant_id: restaurant.id, inputs: [fake_image] },
             headers: auth_for(non_admin)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body["error"]).to eq("file_too_large")
      end

      it "422s on content types the pipeline can't extract from" do
        txt = Rack::Test::UploadedFile.new(StringIO.new("just text"), "text/plain",
                                           original_filename: "menu.txt")

        post "/api/v1/ingestion_runs",
             params: { restaurant_id: restaurant.id, inputs: [txt] },
             headers: auth_for(non_admin)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body["error"]).to eq("unsupported_file_type")
      end

      it "applies the caps to admins too" do
        ENV["INGESTION_MAX_INPUT_FILES"] = "1"

        post "/api/v1/ingestion_runs",
             params: { restaurant_id: restaurant.id,
                       inputs: [fake_image("1.jpg"), fake_image("2.jpg")] },
             headers: auth_for(admin)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    def create_run_as(user)
      post "/api/v1/ingestion_runs",
           params: { restaurant_id: restaurant.id, inputs: [fake_image] },
           headers: auth_for(user)
    end

    describe "per-user daily quota" do
      before { ENV["INGESTION_RUNS_PER_USER_PER_DAY"] = "2" }

      it "allows runs up to the quota, then 429s with the limit in the payload" do
        2.times { create_run_as(non_admin) }
        expect(response).to have_http_status(:created)

        expect { create_run_as(non_admin) }.not_to change(IngestionRun, :count)
        expect(response).to have_http_status(:too_many_requests)
        expect(response.parsed_body).to include("error" => "quota_exceeded", "limit" => 2)
      end

      it "is a rolling 24h window — runs older than 24h don't count" do
        create(:ingestion_run, user: non_admin, restaurant: restaurant, created_at: 25.hours.ago)
        create(:ingestion_run, user: non_admin, restaurant: restaurant, created_at: 1.hour.ago)

        create_run_as(non_admin)
        expect(response).to have_http_status(:created)
      end

      it "is per-user — another user's runs don't count against mine" do
        other = create(:user, password: "password123", is_admin: false)
        2.times { create(:ingestion_run, user: other, restaurant: restaurant) }

        create_run_as(non_admin)
        expect(response).to have_http_status(:created)
      end

      it "admins bypass the quota" do
        3.times { create_run_as(admin) }
        expect(response).to have_http_status(:created)
      end

      it "rejects over-quota callers BEFORE doing any outbound URL fetch (Phase 6.1.2)" do
        2.times { create(:ingestion_run, user: non_admin, restaurant: restaurant) }
        expect(UrlFetcher).not_to receive(:fetch)

        post "/api/v1/ingestion_runs",
             params: { restaurant_id: restaurant.id, source_url: "https://example.com/menu" },
             headers: auth_for(non_admin)

        expect(response).to have_http_status(:too_many_requests)
      end
    end

    describe "global daily cost ceiling" do
      before { ENV["INGESTION_DAILY_COST_CEILING_CENTS"] = "1000" }

      it "503s non-admin creation once today's spend reaches the ceiling" do
        create(:ingestion_run, user: admin, restaurant: restaurant, api_cost_cents: 1_000)

        expect { create_run_as(non_admin) }.not_to change(IngestionRun, :count)
        expect(response).to have_http_status(:service_unavailable)
        expect(response.parsed_body["error"]).to eq("cost_ceiling_reached")
      end

      it "ignores spend from previous days" do
        create(:ingestion_run, user: admin, restaurant: restaurant,
                               api_cost_cents: 5_000, created_at: 2.days.ago)

        create_run_as(non_admin)
        expect(response).to have_http_status(:created)
      end

      it "admins bypass the ceiling" do
        create(:ingestion_run, user: admin, restaurant: restaurant, api_cost_cents: 9_999)

        create_run_as(admin)
        expect(response).to have_http_status(:created)
      end
    end
  end

  describe "GET /api/v1/ingestion_runs/:id" do
    let(:run) { create(:ingestion_run, restaurant: restaurant, user: non_admin) }

    it "lets the run's owner read it" do
      get "/api/v1/ingestion_runs/#{run.id}", headers: auth_for(non_admin)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["id"]).to eq(run.id)
    end

    it "lets an admin read any run" do
      get "/api/v1/ingestion_runs/#{run.id}", headers: auth_for(admin)
      expect(response).to have_http_status(:ok)
    end

    it "404s for a different non-admin user" do
      stranger = create(:user, password: "password123", is_admin: false)
      get "/api/v1/ingestion_runs/#{run.id}", headers: auth_for(stranger)
      expect(response).to have_http_status(:not_found)
    end

    it "401s without a token" do
      get "/api/v1/ingestion_runs/#{run.id}"
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
