# frozen_string_literal: true

require "vips"

module Tools
  module Restaurants
    # The agent never sees an upload's pixels (see SetRestaurantBranding),
    # so this is how it learns an image's shape before choosing a crop.
    # Reads the header only; nothing is decoded, written, or attached.
    class InspectImage < Tools::Base
      audience :user

      tool_name "inspect_image"
      title "Size up an uploaded image"
      description <<~TEXT
        The size of an image the caller uploaded, and what each branding
        slot (see set_restaurant_branding) would do to it: the target
        shape, the box a center crop would keep, how much of each side it
        trims, and whether the image is smaller than the slot.

        Use it before set_restaurant_branding when cropping matters. It
        cannot tell you what is in the picture — ask the owner which part
        to keep if a crop trims a lot.
      TEXT

      input_schema(
        properties: {
          attachment_id: { type: "string", description: "Attachment id from the upload endpoint." }
        },
        required: [ "attachment_id" ],
        additionalProperties: false
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true)

      running_description { "Checking the image size" }

      # EXIF orientations that turn the stored image a quarter-turn;
      # StripMetadata autorotates, so the upright size is what gets cropped.
      QUARTER_TURNS = (5..8)

      def self.perform(context:, attachment_id:)
        blob = owned_upload!(attachment_id, context.user!)
        unless HasPhotoValidation::ALLOWED_PHOTO_TYPES.include?(blob.content_type)
          raise Errors::InvalidArgument, "That attachment is not an image."
        end

        width, height = upright_size(blob)
        sizes = ::Restaurants::Branding::SIZES
        ok(
          attachment_id: attachment_id,
          content_type:  blob.content_type,
          width:         width,
          height:        height,
          aspect_ratio:  width.fdiv(height).round(2),
          fits:          sizes.to_h { |slot, size| [ slot, fit(slot, size, width, height) ] }
        )
      end

      def self.upright_size(blob)
        blob.open do |file|
          image = Vips::Image.new_from_file(file.path, access: :sequential)
          orientation = image.get_typeof("orientation").zero? ? 1 : image.get("orientation")
          QUARTER_TURNS.cover?(orientation) ? [ image.height, image.width ] : [ image.width, image.height ]
        end
      rescue Vips::Error
        raise Errors::InvalidArgument, "We could not read that image."
      end

      def self.fit(slot, size, width, height)
        plan = Images::Fit.plan(width, height, size:)
        {
          target:              { width: size[0], height: size[1], aspect: ::Restaurants::Branding::ASPECTS.fetch(slot) },
          center_crop:         plan.crop,
          trimmed:             plan.trimmed,
          stored:              plan.stored,
          smaller_than_target: plan.smaller_than_target
        }
      end
      private_class_method :upright_size, :fit
    end
  end
end
