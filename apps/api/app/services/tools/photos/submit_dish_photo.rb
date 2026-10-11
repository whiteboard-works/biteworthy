# frozen_string_literal: true

module Tools
  module Photos
    # The chat and MCP door to the diner dish-photo queue — the same
    # DishPhotos::Submit the REST endpoint calls, so the strip, the rate
    # limits, and the credit name have one spelling. Bytes never enter the
    # agent's context: the client uploads to POST /attachments and passes
    # the signed id here.
    #
    # The REST form asks the diner to tick "I took this photo". Here the
    # tick is the confirmation card: `confirm_when { true }` parks the call
    # in manual and accept_edits, and the sentence the user approves is
    # declared below rather than phrased by the model. `auto` mode and a
    # `skip_confirmations` account have opted out of every card, this one
    # included; over MCP the gate is the documented two-call protocol.
    class SubmitDishPhoto < Tools::Base
      audience :user

      tool_name "submit_dish_photo"
      title "Submit a photo of a dish"
      description <<~TEXT
        Send the user's photo of a dish to the moderation queue. A moderator
        decides whether it becomes the dish's photo; nothing changes on the
        menu until then (an admin's photo is approved on the spot). For the
        restaurant's verified owner, `set_item_photo` puts it on the dish
        directly instead.

        Pass the dish's id (from get_menu) and the attachment id from the
        upload. The user must confirm they took the photo themselves;
        never claim it for them. Location data is stripped before the photo is stored.
      TEXT

      input_schema(
        properties: {
          item_id:       { type: "string", description: "The dish's UUID, from get_menu." },
          attachment_id: { type: "string", description: "Attachment id of the photo." }
        },
        required: %w[item_id attachment_id],
        additionalProperties: false
      )

      # Idempotent because DishPhotos::Submit returns the existing
      # submission for the same upload — a confirmation grant is reusable
      # for its TTL, and `confirmation_gate_spec` requires this.
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true)
      confirm_when { true }
      # Not unrecoverable as data (a pending submission can be withdrawn),
      # but an attestation is the user's to make, and accept_edits is a
      # standing yes to edits only. True keeps the card in that mode.
      unrecoverable_when { true }

      confirmation_prompt do |args|
        dish = Item.includes(:restaurant).find_by(id: args[:item_id])
        name = dish ? "#{dish.name} at #{dish.restaurant.name}" : "this dish"
        "Submit this photo of #{name} for review? You're confirming you took this photo " \
          "yourself and BiteWorthy may show it on the dish with your name as credit."
      end

      running_description { "Submitting the dish photo" }

      def self.perform(context:, item_id:, attachment_id:)
        user = context.user!
        item = Item.published.joins(:restaurant).merge(Restaurant.published).find(item_id)

        submission = DishPhotos::Submit.call(
          item:, user:, photo: owned_upload!(attachment_id, user), owns_rights: true
        )

        ok(
          submission: DishPhotos::Serialize.diner_row(submission, host: context.public_host),
          item:       { id: item.id, name: item.name },
          note:       note_for(submission)
        )
      rescue DishPhotos::Submit::RateLimited => e
        raise Errors::Error.new(e.message, code: e.code)
      rescue Images::StripMetadata::Unprocessable => e
        raise Errors::Error.new(e.message, code: e.code)
      end

      # An admin's submission is approved onto the dish on the spot
      # (DishPhotos::Submit); everyone else's waits for a moderator.
      def self.note_for(submission)
        case submission.status
        when "approved" then "Approved and now the dish's photo."
        when "pending"  then "Queued for a moderator. The dish keeps its current photo until one approves it."
        else "This upload was already submitted for this dish and is #{submission.status}."
        end
      end
      private_class_method :note_for
    end
  end
end
