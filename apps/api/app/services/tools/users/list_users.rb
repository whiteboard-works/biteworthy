# frozen_string_literal: true

module Tools
  module Users
    class ListUsers < Tools::AdminBase
      tool_name "list_users"
      title "Search the user roster"
      description <<~TEXT
        Find accounts by email, handle, or display name, newest first, with
        how many reviews and menu scans each has contributed.

        This returns email addresses. Use it to answer a specific question —
        "who is this handle", "who scanned that menu" — and quote back only
        what was asked for. Do not dump the roster into a conversation.

        Dietary profiles are not here and are not admin-readable. Somebody's
        avoid list is a health record.
      TEXT

      input_schema(
        properties: {
          q:        { type: "string", description: "Substring match on email, handle, or display name." },
          admins_only: { type: "boolean", description: "Only accounts with admin rights." },
          limit:    { type: "integer", description: "Max rows, 1–100. Default 25." },
          offset:   { type: "integer", description: "Rows to skip, for paging." }
        }
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true)

      DEFAULT_LIMIT = 25
      MAX_LIMIT     = 100

      def self.perform(context:, q: nil, admins_only: false, limit: nil, offset: nil)
        context.admin!

        scope = User.order(created_at: :desc)
        scope = scope.where(is_admin: true) if admins_only
        scope = search(scope, q) if q.present?

        page = scope.offset(clamp_offset(offset))
                    .limit(clamp_limit(limit, default: DEFAULT_LIMIT, max: MAX_LIMIT))
                    .to_a
        ok(users: rows(page), total: scope.count)
      end

      def self.search(scope, query)
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query.to_s.strip)}%"
        scope.where("email ILIKE :q OR handle ILIKE :q OR display_name ILIKE :q", q: pattern)
      end
      private_class_method :search

      # Grouped counts rather than one query per row.
      def self.rows(page)
        ids = page.map(&:id)
        reviews = Review.where(user_id: ids).group(:user_id).count
        scans   = IngestionRun.where(user_id: ids).group(:user_id).count

        page.map do |user|
          {
            id:            user.id,
            email:         user.email,
            handle:        user.handle,
            display_name:  user.display_name,
            is_admin:      user.is_admin,
            reviews_count: reviews[user.id] || 0,
            scans_count:   scans[user.id] || 0,
            created_at:    user.created_at
          }
        end
      end
      private_class_method :rows
    end
  end
end
