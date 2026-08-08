# frozen_string_literal: true

module Tools
  module Profile
    class SetStrictness < Tools::Base
      audience :user

      tool_name "set_strictness"
      title "Set filter strictness"
      description <<~TEXT
        Set how the caller's filter treats data we are not certain about.

        "strict"   — also hide any dish whose ingredients are not
                     human-confirmed. The right setting for a real allergy:
                     it hides more, including safe dishes we have not yet
                     verified.
        "balanced" — hide only on a confirmed match against the avoid lists.
        "relaxed"  — same matching as balanced; reserved for future loosening.

        Moving away from "strict" un-hides unverified dishes. Confirm with the
        user before doing that, and say plainly what changes.
      TEXT

      input_schema(
        properties: {
          strictness: {
            type: "string",
            description: "The new strictness setting.",
            enum: %w[relaxed balanced strict]
          }
        },
        required: ["strictness"]
      )

      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true)

      def self.perform(context:, strictness:)
        unless UserProfile::STRICTNESS.include?(strictness)
          raise Errors::InvalidArgument, "strictness must be one of: #{UserProfile::STRICTNESS.join(', ')}."
        end

        profile  = context.user!.profile
        previous = profile.strictness
        profile.update!(strictness: strictness)

        ok(previous_strictness: previous, strictness: profile.strictness)
      end
    end
  end
end
