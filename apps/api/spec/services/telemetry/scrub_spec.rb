require "rails_helper"

RSpec.describe Telemetry::Scrub do
  around do |example|
    previous = ENV["APP_ROLE"]
    ENV["APP_ROLE"] = "worker"
    example.run
    ENV["APP_ROLE"] = previous
  end

  describe ".event" do
    # An exception event carries whatever posthog-rails read off the
    # request. The body can be a chat message or a review naming a diet,
    # and the IP is the caller; neither is something a third party's error
    # store should hold.
    it "drops the request body and the caller's address, keeps the exception" do
      event = {
        event: "$exception",
        properties: {
          "$exception_list" => [ { "type" => "RuntimeError" } ],
          "$request_params" => { "message" => "I have celiac" },
          "$ip" => "203.0.113.9",
          "$current_url" => "https://api.bite-worthy.com/api/v1/chat"
        }
      }

      scrubbed = described_class.event(event)

      expect(scrubbed[:properties]).not_to have_key("$request_params")
      expect(scrubbed[:properties]).not_to have_key("$ip")
      expect(scrubbed[:properties]["$exception_list"]).to be_present
      expect(scrubbed[:properties]["$current_url"]).to eq("https://api.bite-worthy.com/api/v1/chat")
    end

    it "tags the event with the Kamal role" do
      event = { event: "$exception", properties: {} }
      expect(described_class.event(event)[:properties]["service.role"]).to eq("worker")
    end

    it "leaves an event without properties alone" do
      expect(described_class.event({ event: "x" })).to eq({ event: "x" })
    end
  end

  describe ".log" do
    it "blanks the client address on Rails' request line, IPv6 included" do
      record = { body: 'Started GET "/api/v1/me" for 2a02:1234:5678:abcd::1 at 2026-10-10 14:00:00 +0000' }
      expect(described_class.log(record)[:body])
        .to eq('Started GET "/api/v1/me" for <ip> at 2026-10-10 14:00:00 +0000')
    end

    it "blanks IPv4 addresses and emails anywhere in the line" do
      record = { body: "throttled 198.51.100.7 after signup by someone@example.com" }
      expect(described_class.log(record)[:body]).to eq("throttled <ip> after signup by <email>")
    end

    it "redacts credentials: key prefixes, bearer tokens, JWTs, and URL passwords" do
      record = {
        body: "sk-ant-api03-abc Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.sig " \
              "postgresql://user:hunter2@db.example.com/x re_D4Tw9LZ1JNdEy5SCZfxVqtXXEZN ghp_abcdef"
      }
      body = described_class.log(record)[:body]
      expect(body).not_to include("api03-abc", "hunter2", "D4Tw9LZ1", "ghp_abcdef", "eyJhbGci")
      expect(body).to include("sk-ant-<redacted>", "Bearer <redacted>", "://<redacted>@", "re_<redacted>", "ghp_<redacted>")
    end

    it "does not mistake a timestamp for an address" do
      record = { body: "Completed 200 OK in 12ms at 2026-10-10 14:00:00" }
      expect(described_class.log(record)[:body]).to eq("Completed 200 OK in 12ms at 2026-10-10 14:00:00")
    end

    it "tags the record with the Kamal role" do
      expect(described_class.log({ body: "x" })[:attributes]).to eq("service.role" => "worker")
    end
  end
end

RSpec.describe Telemetry::Scrub, "the parts the first review found missing" do
  describe ".event" do
    it "scrubs the exception message and the context, and drops the referrer with its query" do
      event = {
        event: "$exception",
        properties: {
          "$exception_list" => [ { "type" => "ActiveRecord::RecordNotUnique",
                                   "value" => "Key (email)=(someone@example.com) already exists" } ],
          "$referrer" => "https://bite-worthy.com/u/alice?token=eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.sig",
          "$current_url" => "https://api.bite-worthy.com/api/v1/restaurants/x/items?profile=celiac&strictness=strict",
          "$context_path" => "/api/v1/users/alice"
        }
      }

      properties = described_class.event(event)[:properties]

      expect(properties["$exception_list"].first["value"]).to eq("Key (email)=(<email>) already exists")
      expect(properties["$current_url"]).to eq("https://api.bite-worthy.com/api/v1/restaurants/x/items?profile=<q>&strictness=<q>")
      expect(properties).not_to have_key("$referrer")
      expect(properties["$context_path"]).to eq("/api/v1/users/:handle")
    end

    it "reaches strings nested in a context hash or array" do
      event = { event: "$exception", properties: { "$context_detail" => { "who" => [ "a@b.co" ], "n" => 1 } } }
      expect(described_class.event(event)[:properties]["$context_detail"]).to eq("who" => [ "<email>" ], "n" => 1)
    end
  end

  describe ".log" do
    it "drops the health check's lines, which silence_healthcheck_path cannot reach" do
      expect(described_class.log({ body: 'Started GET "/up" for 10.0.0.1 at 2026-10-10 14:00:00 +0000' })).to be_nil
      expect(described_class.log({ body: "Completed 200 OK in 1ms", attributes: { "url.path" => "/up" } })).to be_nil
      expect(described_class.log({ body: 'Started GET "/upload" for 10.0.0.1 at 2026-10-10 14:00:00 +0000' })).not_to be_nil
    end

    it "drops the Parameters line: a chat message or a review sits under keys the filter does not name" do
      record = { body: '  Parameters: {"message"=>"I have celiac and a peanut allergy", "conversation_id"=>"1"}' }
      expect(described_class.log(record)).to be_nil
      review = { body: '  Parameters: {"review"=>{"body"=>"made me sick", "rating"=>1}}' }
      expect(described_class.log(review)).to be_nil
    end

    it "keeps a grounding flag but not what the model said about the answer" do
      record = { body: "[chat] grounding flagged conversation 42: the answer calls the pad thai safe for a peanut allergy" }
      expect(described_class.log(record)[:body]).to eq("[chat] grounding flagged conversation 42: <model text>")
    end

    it "blanks every query value: verify tokens, share tokens, the diet a menu is filtered by" do
      record = { body: "[RestaurantClaimMailer] verify URL for Cafe: https://bite-worthy.com/claim/verify?t=abc123&x=1 " \
                       'Started GET "/r/cafe?p=eyJhIjoxfQ&profile=celiac" for 10.0.0.1 at 2026-10-10 00:00:00' }
      body = described_class.log(record)[:body]
      expect(body).to include("verify?t=<q>&x=<q>", '"/r/cafe?p=<q>&profile=<q>"')
      expect(body).not_to include("abc123", "eyJhIjoxfQ", "celiac")
    end

    it "drops job arguments: Devise's mail job carries the raw reset token as a bare string" do
      token = "pXk3Qz9vTbLm2RwYc7HdN1sAeF4gJuVo"
      enqueued = { body: "Enqueued ActionMailer::MailDeliveryJob (Job ID: 9b1) to SolidQueue(default) with arguments: " \
                         "\"DeviseMailer\", \"reset_password_instructions\", \"deliver_now\", {args: [#<GlobalID:0x1 gid://biteworthy/User/3>, \"#{token}\"]}" }
      performing = { body: "Performing ActionMailer::MailDeliveryJob (Job ID: 9b1) from SolidQueue(default) enqueued at 2026-10-10T00:00:00Z with arguments: \"DeviseMailer\", \"#{token}\"" }
      expect(described_class.log(enqueued)[:body])
        .to eq("Enqueued ActionMailer::MailDeliveryJob (Job ID: 9b1) to SolidQueue(default) with arguments: <redacted>")
      expect(described_class.log(performing)[:body]).to end_with("enqueued at 2026-10-10T00:00:00Z with arguments: <redacted>")
      expect(described_class.log(performing)[:body]).not_to include(token)
    end

    it "blanks a query value past an apostrophe" do
      record = { body: %(Started GET "/search?q=Bob's-celiac-plan&page=2" for 10.0.0.1 at 2026-10-10 00:00:00) }
      expect(described_class.log(record)[:body]).to eq(%(Started GET "/search?q=<q>&page=<q>" for <ip> at 2026-10-10 00:00:00))
    end

    it "redacts Active Storage paths: the signed blob id is a bearer credential" do
      path = "/rails/active_storage/blobs/redirect/eyJfcmFpbHMiOnsiZGF0YSI6MX19--abcdef0123456789/menu%20photo.jpg"
      record = { body: "Started GET \"#{path}\" for 10.0.0.1 at 2026-10-10 00:00:00", attributes: { "url.path" => path } }
      scrubbed = described_class.log(record)
      expect(scrubbed[:body]).to eq('Started GET "/rails/active_storage/<redacted>" for <ip> at 2026-10-10 00:00:00')
      expect(scrubbed[:attributes]["url.path"]).to eq("/rails/active_storage/<redacted>")
      disk = { body: "Processing /rails/active_storage/disk/eyJfcmFpbHMiOnsibWVzc2FnZSI6IkJBaDdDV2tpIn19--ff" }
      expect(described_class.log(disk)[:body]).to eq("Processing /rails/active_storage/<redacted>")
    end

    it "masks the person out of the by-handle route, in the body and the path attribute" do
      record = { body: "Processing /api/v1/users/alice_1", attributes: { "url.path" => "/api/v1/users/alice_1" } }
      scrubbed = described_class.log(record)
      expect(scrubbed[:body]).to eq("Processing /api/v1/users/:handle")
      expect(scrubbed[:attributes]["url.path"]).to eq("/api/v1/users/:handle")
    end
  end
end
