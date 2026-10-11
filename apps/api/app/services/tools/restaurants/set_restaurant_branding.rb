# frozen_string_literal: true

module Tools
  module Restaurants
    # Owner-facing, unlike the rest of this directory: `audience :user` is
    # the outer gate, Restaurants::Branding.authorize! (verified owner or
    # admin) is the real one. Bytes never enter the agent's context — the
    # client uploads to POST /attachments and passes the signed ids here,
    # the same handoff the review and scan tools use.
    class SetRestaurantBranding < Tools::Base
      audience :user

      tool_name "set_restaurant_branding"
      title "Set a restaurant's logo and banner"
      description <<~TEXT
        Upload or remove a restaurant's logo and banner. Only the verified
        owner (see claim_restaurant) or an admin can do this.

        Pass attachment ids from the upload endpoint; each is an image
        (JPEG, PNG, WebP, or HEIC, up to 15 MB). The logo shows beside the
        restaurant's name on every card and page header; the banner runs
        across the top of its page. A new image replaces the old one, and
        `remove_logo` / `remove_banner` clear one. Omitted images are left
        alone.
      TEXT

      input_schema(
        properties: {
          restaurant:           { type: "string", description: "Restaurant slug or UUID." },
          logo_attachment_id:   { type: "string", description: "Attachment id of the new logo." },
          banner_attachment_id: { type: "string", description: "Attachment id of the new banner." },
          remove_logo:          { type: "boolean", description: "Clear the current logo." },
          remove_banner:        { type: "boolean", description: "Clear the current banner." }
        },
        required: [ "restaurant" ],
        additionalProperties: false
      )

      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: true)
      # The old image is purged, but a fresh upload puts a new one back.
      unrecoverable_when { false }

      running_description { "Updating the restaurant's branding" }

      def self.perform(context:, restaurant:, logo_attachment_id: nil, banner_attachment_id: nil,
                       remove_logo: false, remove_banner: false)
        user   = context.user!
        record = Restaurant.kept.find_by_id_or_slug!(restaurant)
        ::Restaurants::Branding.authorize!(user, record)

        if [ logo_attachment_id, banner_attachment_id ].all?(&:blank?) && !remove_logo && !remove_banner
          raise Errors::InvalidArgument, "Pass an image to set or a flag to remove."
        end

        ::Restaurants::Branding.apply!(
          record,
          logo:          blob_for(logo_attachment_id, user),
          banner:        blob_for(banner_attachment_id, user),
          remove_logo:   remove_logo == true,
          remove_banner: remove_banner == true
        )

        ok(
          restaurant: { id: record.id, slug: record.slug, name: record.name },
          logo_url:   url_for(context, record.logo, :thumb),
          banner_url: url_for(context, record.banner, :card)
        )
      rescue ::Restaurants::Branding::Forbidden => e
        raise Errors::Forbidden, e.message
      rescue Images::StripMetadata::Unprocessable => e
        raise Errors::InvalidArgument, e.message
      end

      # Same ownership check as the review photo: the blob must have been
      # uploaded by this caller, so one account cannot brand with another's
      # upload by guessing an id.
      def self.blob_for(signed_id, user)
        return nil if signed_id.blank?

        blob = ActiveStorage::Blob.find_signed(signed_id)
        unless blob && blob.metadata["uploaded_by_user_id"].to_s == user.id.to_s
          raise Errors::InvalidArgument, "Attachment not found."
        end
        blob
      end
      private_class_method :blob_for

      def self.url_for(context, attachment, variant)
        return nil unless attachment.attached?

        Rails.application.routes.url_helpers.rails_representation_url(
          attachment.variant(variant), host: context.public_host
        )
      end
      private_class_method :url_for
    end
  end
end
