module Api
  module V1
    module Admin
      # User management for the web admin — deliberately minimal:
      # list/search plus the is_admin toggle. No destroy (account
      # deletion has its own legal-remediation path), no email/handle
      # editing. The self-demotion guard guarantees the acting admin
      # survives, so the system can never reach zero admins through
      # this API.
      class UsersController < BaseController
        DEFAULT_LIMIT = 25
        MAX_LIMIT     = 100

        def index
          scope = User.order(created_at: :desc)
          scope = scope.where(is_admin: true) if params[:is_admin].to_s == "true"

          if params[:q].present?
            q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)}%"
            scope = scope.where(
              "email ILIKE :q OR handle ILIKE :q OR display_name ILIKE :q", q: q
            )
          end

          total  = scope.count
          limit  = page_limit(default: DEFAULT_LIMIT, max: MAX_LIMIT)
          offset = page_offset
          page   = scope.limit(limit).offset(offset).to_a

          review_counts = Review.where(user_id: page.map(&:id)).group(:user_id).count
          run_counts    = IngestionRun.where(user_id: page.map(&:id)).group(:user_id).count

          render json: {
            users: page.map do |user|
              serialize_user(user).merge(
                reviews_count:        review_counts[user.id] || 0,
                ingestion_runs_count: run_counts[user.id] || 0
              )
            end,
            pagination: { total: total, limit: limit, offset: offset }
          }
        end

        def update
          user = User.find(params[:id])
          is_admin = ActiveModel::Type::Boolean.new.cast(params.require(:is_admin))

          if user.id == current_user.id && is_admin == false
            render json: { error: "cannot_demote_self" }, status: :unprocessable_entity
            return
          end

          # The super tier is granted from a shell and revoked from a
          # shell — that is the property that keeps "no spend ceiling"
          # off the list of things one admin can hand another. Demoting a
          # super admin here would also violate the
          # `super_admin_implies_admin` CHECK constraint, so without this
          # the honest refusal below would arrive as a 500.
          if user.is_super_admin? && is_admin == false
            render json: { error: "cannot_demote_super_admin" }, status: :unprocessable_entity
            return
          end

          user.update!(is_admin: is_admin == true)
          render json: serialize_user(user)
        end

        private

        def serialize_user(user)
          {
            id:             user.id,
            email:          user.email,
            handle:         user.handle,
            display_name:   user.display_name,
            provider:       user.provider,
            is_admin:       user.is_admin,
            # Read-only here — this endpoint cannot set it. Surfaced so
            # the admin list can show why the toggle is refused rather
            # than presenting a control that always fails.
            is_super_admin: user.is_super_admin,
            created_at:     user.created_at
          }
        end
      end
    end
  end
end
