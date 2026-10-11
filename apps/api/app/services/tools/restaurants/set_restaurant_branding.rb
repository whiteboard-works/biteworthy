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
        (JPEG, PNG, WebP, or HEIC, up to 15 MB). A new image replaces the
        old one, and `remove_logo` / `remove_banner` clear one. Omitted
        images are left alone.

        Each slot has a fixed shape, and images are cropped to it:
        - Logo: square, 1:1, stored up to 400×400. Shown as a small square
          (about 48–56px) beside the name on every card and page header,
          so a wordmark or wide sign reads poorly there.
        - Banner: 8:3, stored up to 1600×600. Runs full-width across the
          top of the restaurant's page.
        Images are never enlarged, so one smaller than that looks soft.

        You cannot see the image. Call `inspect_image` first to get its
        size and what a center crop would trim, and if that is a lot, ask
        the owner which part to keep. Then pass `logo_crop` /
        `banner_crop`: an `anchor` (which edge to keep while trimming to
        shape; default center) and/or a box `x, y, w, h` in fractions of
        the image (cut first, then trimmed to shape). The reply's
        `adjustments` says exactly what was kept.
      TEXT

      CROP_SCHEMA = {
        type: "object",
        description: "Which part of the new image to keep. Omit to center-crop.",
        properties: {
          anchor: { type: "string", enum: Images::Fit::ANCHORS, description: "Edge kept when trimming to shape." },
          x:      { type: "number", minimum: 0, maximum: 1, description: "Box left, fraction of width." },
          y:      { type: "number", minimum: 0, maximum: 1, description: "Box top, fraction of height." },
          w:      { type: "number", exclusiveMinimum: 0, maximum: 1, description: "Box width, fraction of width; x + w <= 1." },
          h:      { type: "number", exclusiveMinimum: 0, maximum: 1, description: "Box height, fraction of height; y + h <= 1." }
        },
        additionalProperties: false
      }.freeze

      input_schema(
        properties: {
          restaurant:           { type: "string", description: "Restaurant slug or UUID." },
          logo_attachment_id:   { type: "string", description: "Attachment id of the new logo." },
          banner_attachment_id: { type: "string", description: "Attachment id of the new banner." },
          remove_logo:          { type: "boolean", description: "Clear the current logo." },
          remove_banner:        { type: "boolean", description: "Clear the current banner." },
          logo_crop:            CROP_SCHEMA,
          banner_crop:          CROP_SCHEMA
        },
        required: [ "restaurant" ],
        additionalProperties: false
      )

      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: true)
      # The old image is purged, but a fresh upload puts a new one back.
      unrecoverable_when { false }

      running_description { "Updating the restaurant's branding" }

      def self.perform(context:, restaurant:, logo_attachment_id: nil, banner_attachment_id: nil,
                       remove_logo: false, remove_banner: false, logo_crop: nil, banner_crop: nil)
        user   = context.user!
        record = Restaurant.kept.find_by_id_or_slug!(restaurant)
        ::Restaurants::Branding.authorize!(user, record)

        if [ logo_attachment_id, banner_attachment_id ].all?(&:blank?) && !remove_logo && !remove_banner
          raise Errors::InvalidArgument, "Pass an image to set or a flag to remove."
        end

        adjustments = ::Restaurants::Branding.apply!(
          record,
          logo:          blob_for(logo_attachment_id, user),
          banner:        blob_for(banner_attachment_id, user),
          remove_logo:   remove_logo == true,
          remove_banner: remove_banner == true,
          logo_crop:     logo_crop,
          banner_crop:   banner_crop
        )

        ok(
          restaurant: { id: record.id, slug: record.slug, name: record.name },
          logo_url:   ::Restaurants::Branding.variant_url(record.logo, :thumb, host: context.public_host),
          banner_url: ::Restaurants::Branding.variant_url(record.banner, :card, host: context.public_host),
          adjustments: adjustments
        )
      rescue ::Restaurants::Branding::Forbidden => e
        raise Errors::Forbidden, e.message
      rescue Images::StripMetadata::Unprocessable => e
        raise Errors::InvalidArgument, e.message
      end

      def self.blob_for(signed_id, user)
        signed_id.blank? ? nil : owned_upload!(signed_id, user)
      end
      private_class_method :blob_for
    end
  end
end
