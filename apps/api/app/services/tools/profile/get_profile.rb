# frozen_string_literal: true

module Tools
  module Profile
    # What the caller currently avoids, likes, and dislikes.
    class GetProfile < Tools::Base
      audience :user

      tool_name "get_profile"
      title "Get dietary profile"
      description <<~TEXT
        The signed-in caller's dietary settings: what they avoid (hard filter —
        these hide dishes), what they like and dislike (soft signals — these
        only reorder, never hide), their strictness setting, and which preset
        they started from.

        Read this before changing anything, and before answering "can I eat
        here?" without naming a restaurant.
      TEXT

      input_schema(properties: {}, required: [])

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true)

      running_description { "Checking what you avoid" }

      def self.perform(context:)
        ok(Serializer.call(context.user!.profile))
      end
    end
  end
end
