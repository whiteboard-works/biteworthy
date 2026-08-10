module Api
  module V1
    module Admin
      # One owner for what `DELETE /api/v1/admin/<thing>/:id` means.
      #
      #   DELETE …            → archive. The row stays, flipped to
      #                         whichever tombstone that resource
      #                         already has, and stops being visible.
      #   DELETE …?hard=true  → the row is gone. Super admins only.
      #
      # Soft is the default because most of what an admin wants to
      # delete is a mistake to be hidden, not evidence to be destroyed —
      # and because a hidden restaurant can come back, while a deleted
      # one takes its menus, items, reviews and scan history with it.
      #
      # A non-super admin asking for `hard=true` gets a 404, not a 403,
      # matching the convention `require_admin!` set: the response
      # never confirms that a capability exists on the other side of a
      # permission it lacks.
      #
      # Only restaurants and ingestion runs archive here. The other
      # four already had a soft delete before this concern existed —
      # `status: "removed"` on an item, `POST /hide` on a review,
      # `rejected` on a suggestion — and reaching those through DELETE
      # would mean inventing a value to write. `Review#hide!` takes a
      # reason from a closed list of *editorial* judgments (spam,
      # abuse, duplicate, off_topic); a delete button that recorded
      # "spam" because the enum had nothing else would put a false
      # reason in a moderation audit trail. So a bare DELETE on those
      # four refuses and names the endpoint that does it properly.
      module Deletable
        extend ActiveSupport::Concern

        private

        def hard_delete_requested?
          ActiveModel::Type::Boolean.new.cast(params[:hard]) == true
        end

        def render_soft_delete_unsupported(use:)
          render json: { error: "soft_delete_unsupported", use: use },
                 status: :unprocessable_entity
        end

        def require_super_admin!
          return true if current_user&.is_super_admin?

          render json: { error: "not_found" }, status: :not_found
          false
        end

        # Caller pattern, matching the `gate_owner!(...) or return`
        # precedent in SuggestionsController:
        #
        #   def destroy
        #     authorize_hard_delete! or return
        #     …
        def authorize_hard_delete!
          return true unless hard_delete_requested?

          require_super_admin!
        end

        # Every hard delete answers the same way. The body carries the
        # id because the client has just removed a row from a list and
        # the response is the only confirmation of *which* one.
        def render_hard_deleted(record)
          render json: { id: record.id, deleted: true }
        end
      end
    end
  end
end
