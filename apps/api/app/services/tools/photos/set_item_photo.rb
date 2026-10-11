# frozen_string_literal: true

module Tools
  module Photos
    # The direct door: the restaurant's verified owner or an admin puts a
    # photo on a dish with no moderation step — the same gate as branding
    # (Restaurants::Branding.authorize!). Everyone else goes through
    # `submit_dish_photo`.
    #
    # Unlike the admin item editor's photo path, the upload is rewritten
    # through Images::StripMetadata, so an owner's phone photo lands
    # without EXIF/GPS.
    class SetItemPhoto < Tools::Base
      audience :user

      tool_name "set_item_photo"
      title "Set a dish's photo"
      description <<~TEXT
        Put a photo on a dish right away, replacing its current one. Only the
        restaurant's verified owner (get_restaurant's `managed_by_caller`)
        or an admin can do this; for anyone else use `submit_dish_photo`,
        which goes to a moderator.

        Pass a published dish's id (from get_menu) and the attachment id from the upload (JPEG, PNG, WebP, or HEIC). Location
        data is stripped before the photo is stored.
      TEXT

      input_schema(
        properties: {
          item_id:       { type: "string", description: "The dish's UUID." },
          attachment_id: { type: "string", description: "Attachment id of the photo." }
        },
        required: %w[item_id attachment_id],
        additionalProperties: false
      )

      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: true)
      # The replaced photo is purged; a dish with no photo yet loses nothing.
      unrecoverable_when { |args| Item.find_by(id: args[:item_id])&.photo&.attached? != false }

      confirmation_prompt do |args|
        dish = Item.includes(:restaurant).find_by(id: args[:item_id])
        next "Put this photo on the dish?" unless dish

        verb = dish.photo.attached? ? "Replace the photo on" : "Put this photo on"
        "#{verb} #{dish.name} at #{dish.restaurant.name}? It shows to everyone right away."
      end

      running_description { "Setting the dish photo" }

      def self.perform(context:, item_id:, attachment_id:)
        user = context.user!
        item = Item.published.joins(:restaurant).merge(Restaurant.published).find(item_id)
        authorize!(user, item.restaurant)

        upload = owned_upload!(attachment_id, user)
        attach_exclusively!(item, stored_copy(upload))

        ok(
          item:      { id: item.id, name: item.name },
          photo_url: DishPhotos::Serialize.variant_url(item.photo, :card, host: context.public_host)
        )
      rescue Images::StripMetadata::Unprocessable => e
        raise Errors::Error.new(e.message, code: e.code)
      end

      # Stored before any lock, so a storage failure leaves the dish as it
      # was rather than committed to a blob that never landed.
      def self.stored_copy(upload)
        stripped = Images::StripMetadata.call(upload, filename: upload.filename.to_s,
                                                      content_type: upload.content_type)
        ActiveStorage::Blob.create_and_upload!(
          io: stripped.io, filename: stripped.filename, content_type: stripped.content_type
        )
      end
      private_class_method :stored_copy

      # Same shape as DishPhotos::Moderate: under the item lock, attach,
      # drop any other photo rows, clear the diner credit; purge the
      # replaced blobs only once the new one is committed.
      def self.attach_exclusively!(item, blob)
        old_blob_ids = []
        committed = false
        begin
          item.with_lock do
            old_blob_ids = ActiveStorage::Attachment.where(record: item, name: "photo").pluck(:blob_id)
            item.photo.attach(blob)
            ActiveStorage::Attachment.where(record: item, name: "photo").where.not(blob_id: blob.id).delete_all
            item.update!(photo_submission_id: nil)
          end
          committed = true
        ensure
          blob.purge unless committed
        end
        ActiveStorage::Blob.where(id: old_blob_ids - [ blob.id ]).find_each(&:purge_later)
        preprocess_card!(item)
      end
      private_class_method :attach_exclusively!

      def self.preprocess_card!(item)
        item.photo.variant(:card).processed
      rescue StandardError => e
        Rails.logger.warn("[tools] set_item_photo variant preprocessing failed: #{e.class} #{e.message}")
      end
      private_class_method :preprocess_card!

      def self.authorize!(user, restaurant)
        return if ::Restaurants::Branding.allowed?(user, restaurant)

        raise Errors::Forbidden,
              "Only the verified owner of #{restaurant.name} or an admin can set a dish photo " \
              "directly. Use submit_dish_photo to send it to a moderator instead."
      end
      private_class_method :authorize!
    end
  end
end
