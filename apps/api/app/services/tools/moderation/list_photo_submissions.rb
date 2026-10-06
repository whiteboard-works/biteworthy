# frozen_string_literal: true

module Tools
  module Moderation
    class ListPhotoSubmissions < Tools::AdminBase
      tool_name "list_photo_submissions"
      title "Dish photos waiting on a moderator"
      description <<~TEXT
        Diner-submitted photos of dishes. Defaults to `pending` — photos that
        have not been approved or rejected yet, and so are not the public dish
        photo. `approved` and `rejected` are the audit trail.

        Approving copies the image onto the dish (or, if the dish already has
        a photo, can leave that photo in place). Rejecting needs a reason the
        submitter can be shown.

        The image itself is stored without camera metadata (no GPS). Look at
        the photo URL in a browser; do not trust a caption that claims to
        identify the dish.
      TEXT

      STATUSES = {
        "pending"  => :pending,
        "approved" => :approved,
        "rejected" => :rejected,
        "all"      => :all
      }.freeze

      input_schema(
        properties: {
          status: {
            type: "string",
            description: "Which slice of the queue. Default 'pending'.",
            enum: STATUSES.keys
          },
          item_id: { type: "string", description: "Optional. Restrict to one dish UUID." },
          limit:   { type: "integer", description: "Max rows, 1–100. Default 25." },
          offset:  { type: "integer", description: "Rows to skip, for paging." }
        }
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true)

      running_description { "Pulling up the dish photo queue" }

      DEFAULT_LIMIT = 25
      MAX_LIMIT     = 100

      def self.perform(context:, status: "pending", item_id: nil, limit: nil, offset: nil)
        context.admin!
        scope_name = STATUSES[status]
        unless scope_name
          raise Errors::InvalidArgument, "status must be one of: #{STATUSES.keys.join(', ')}."
        end

        scope = DishPhotoSubmission.public_send(scope_name)
        scope = scope.where(item_id: item_id) if item_id.present?
        page  = scope.newest_first
                     .includes(:user, item: :restaurant)
                     .offset(clamp_offset(offset))
                     .limit(clamp_limit(limit, default: DEFAULT_LIMIT, max: MAX_LIMIT))

        ok(
          status: status,
          photo_submissions: page.map { |s| queue_row(s, host: context.public_host) },
          total: scope.count
        )
      end

      def self.queue_row(submission, host:)
        item = submission.item
        DishPhotos::Serialize.diner_row(submission, host:).merge(
          author: untrusted(submission.user&.handle || submission.credit_name),
          dish: {
            id: item.id,
            name: untrusted(item.name),
            restaurant: item.restaurant.name,
            has_photo: item.photo.attached?
          }
        )
      end
      private_class_method :queue_row
    end
  end
end
