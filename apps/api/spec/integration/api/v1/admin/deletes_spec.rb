require "swagger_helper"

# The admin delete surface, documented in one place because the rule is
# one rule (Api::V1::Admin::Deletable) applied six times, and reading it
# resource-by-resource hides the shape:
#
#   DELETE …            archive, where the resource has somewhere to
#                       archive *to* — restaurants and ingestion runs.
#   DELETE …?hard=true  the row is gone. Super admins only; a plain
#                       admin gets the same 404 `require_admin!` gives a
#                       non-admin, so the response never confirms the
#                       capability exists.
#
# Items, reviews and suggestions refuse the bare form. Each already has
# a soft delete that predates this concern, and routing DELETE to it
# would mean inventing a value — a review can only be hidden *for* a
# reason, and none of the four permitted reasons means "an admin
# deleted it".
def hard_deleted_schema
  {
    type: :object,
    required: %w[id deleted],
    properties: {
      id:      { type: :string, format: :uuid },
      deleted: { type: :boolean }
    }
  }
end

def soft_delete_unsupported_schema
  {
    type: :object,
    required: %w[error use],
    properties: {
      error: { type: :string },
      use:   { type: :string, description: "The endpoint that does this properly" }
    }
  }
end

RSpec.describe "admin/deletes", type: :request do
  def bearer_for(user)
    token, _ = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
    "Bearer #{token}"
  end

  path "/api/v1/admin/restaurants/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    delete("Archive a restaurant, or destroy it with ?hard=true") do
      tags "Admin"
      produces "application/json"
      security [ { bearerAuth: [] } ]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :hard, in: :query, type: :boolean, required: false,
                description: "Super admins only. Destroys the row and, by " \
                             "`dependent: :destroy`, its menus, sections, " \
                             "items, addresses, hours and everyone's saved rows."

      response(200, "archived — the restaurant with archived_at set") do
        schema type: :object,
               required: %w[id deleted archived_at],
               properties: {
                 id:          { type: :string, format: :uuid },
                 deleted:     { type: :boolean, description: "false — the row was archived, not destroyed" },
                 slug:        { type: :string },
                 name:        { type: :string },
                 status:      { type: :string, enum: Restaurant::STATUSES },
                 archived_at: { type: :string, format: "date-time", nullable: true }
               }
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id) { create(:restaurant).id }
        run_test!
      end

      response(200, "destroyed") do
        schema hard_deleted_schema
        let(:Authorization) { bearer_for(create(:user, :super_admin)) }
        let(:hard) { true }
        let(:id) { create(:restaurant).id }
        run_test!
      end

      response(404, "hard delete requested by a plain admin") do
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:hard) { true }
        let(:id) { create(:restaurant).id }
        run_test!
      end
    end
  end

  path "/api/v1/admin/restaurants/{id}/restore" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    post("Un-archive a restaurant") do
      tags "Admin"
      produces "application/json"
      security [ { bearerAuth: [] } ]
      parameter name: :Authorization, in: :header, type: :string, required: true

      response(200, "the restaurant, archived_at cleared") do
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id) { create(:restaurant, archived_at: Time.current).id }
        run_test!
      end
    end
  end

  path "/api/v1/admin/ingestion_runs/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    delete("Archive an ingestion run, or destroy it with ?hard=true") do
      tags "Admin"
      produces "application/json"
      security [ { bearerAuth: [] } ]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :hard, in: :query, type: :boolean, required: false,
                description: "Super admins only. Takes the run's staged " \
                             "IngestionItems with it; items already promoted " \
                             "to the menu are separate rows and survive."

      response(200, "archived") do
        schema type: :object,
               required: %w[id deleted archived_at],
               properties: {
                 id:          { type: :string, format: :uuid },
                 deleted:     { type: :boolean, description: "false — the row was archived, not destroyed" },
                 archived_at: { type: :string, format: "date-time", nullable: true }
               }
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id) { create(:ingestion_run).id }
        run_test!
      end

      response(200, "destroyed") do
        schema hard_deleted_schema
        let(:Authorization) { bearer_for(create(:user, :super_admin)) }
        let(:hard) { true }
        let(:id) { create(:ingestion_run).id }
        run_test!
      end
    end
  end

  path "/api/v1/admin/ingestion_runs/{id}/restore" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    post("Un-archive an ingestion run") do
      tags "Admin"
      produces "application/json"
      security [ { bearerAuth: [] } ]
      parameter name: :Authorization, in: :header, type: :string, required: true

      response(200, "the run, archived_at cleared") do
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id) { create(:ingestion_run, archived_at: Time.current).id }
        run_test!
      end
    end
  end

  path "/api/v1/admin/items/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    delete("Destroy a menu item (hard only)") do
      tags "Admin"
      produces "application/json"
      security [ { bearerAuth: [] } ]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :hard, in: :query, type: :boolean, required: false,
                description: "Must be true — a bare DELETE is a 422. Super admins only."

      response(200, "destroyed") do
        schema hard_deleted_schema
        let(:Authorization) { bearer_for(create(:user, :super_admin)) }
        let(:hard) { true }
        let(:id) { create(:item).id }
        run_test!
      end

      response(422, "bare DELETE — use status=removed instead") do
        schema soft_delete_unsupported_schema
        let(:Authorization) { bearer_for(create(:user, :super_admin)) }
        let(:id) { create(:item).id }
        run_test!
      end
    end
  end

  path "/api/v1/admin/reviews/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    delete("Destroy a review (hard only)") do
      tags "Admin"
      produces "application/json"
      security [ { bearerAuth: [] } ]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :hard, in: :query, type: :boolean, required: false,
                description: "Must be true — a bare DELETE is a 422. Super admins only. Hiding a review " \
                             "is POST /hide, which records why."

      response(200, "destroyed") do
        schema hard_deleted_schema
        let(:Authorization) { bearer_for(create(:user, :super_admin)) }
        let(:hard) { true }
        let(:id) { create(:review).id }
        run_test!
      end

      response(422, "bare DELETE — use POST /hide instead") do
        schema soft_delete_unsupported_schema
        let(:Authorization) { bearer_for(create(:user, :super_admin)) }
        let(:id) { create(:review).id }
        run_test!
      end
    end
  end

  path "/api/v1/admin/suggestions/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    delete("Destroy a suggestion or restaurant claim (hard only)") do
      tags "Admin"
      produces "application/json"
      security [ { bearerAuth: [] } ]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :hard, in: :query, type: :boolean, required: false,
                description: "Must be true — a bare DELETE is a 422. Super admins only."

      response(200, "destroyed") do
        schema hard_deleted_schema
        let(:Authorization) { bearer_for(create(:user, :super_admin)) }
        let(:hard) { true }
        let(:id) { create(:item_suggestion_pending).id }
        run_test!
      end
    end
  end

  path "/api/v1/admin/users/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    delete("Destroy a user account") do
      tags "Admin"
      produces "application/json"
      security [ { bearerAuth: [] } ]
      parameter name: :Authorization, in: :header, type: :string, required: true
      description "Super admins only, and there is no archive form — the " \
                  "app has no deactivated-account state. Cascades to the " \
                  "profile, reviews, saved rows, overrides, visits, " \
                  "conversations and MCP tokens; suggestions and ingestion " \
                  "runs nullify, so the moderation record survives."

      response(200, "destroyed") do
        schema hard_deleted_schema
        let(:Authorization) { bearer_for(create(:user, :super_admin)) }
        let(:id) { create(:user).id }
        run_test!
      end

      response(404, "requested by a plain admin") do
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id) { create(:user).id }
        run_test!
      end

      response(422, "cannot_delete_self or cannot_delete_super_admin") do
        schema type: :object,
               required: %w[error],
               properties: { error: { type: :string } }
        let(:actor) { create(:user, :super_admin) }
        let(:Authorization) { bearer_for(actor) }
        let(:id) { actor.id }
        run_test!
      end
    end
  end
end
