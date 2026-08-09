# The REST half of ::Taxonomy::Writer: turns its typed refusals into the
# bodies the admin UI already handles. Shared by the ingredients and tags
# controllers so the two resources fail identically — the rules are one
# object now, and how they read on the wire should not be the new place
# they drift.
module TaxonomyErrorResponse
  extend ActiveSupport::Concern

  included do
    rescue_from ::Taxonomy::Writer::InvalidPath do
      render json: { error: "invalid_path" }, status: :unprocessable_entity
    end

    rescue_from ::Taxonomy::Writer::ParentMissing do |error|
      render json: { error: "parent_missing", parent: error.parent }, status: :unprocessable_entity
    end

    rescue_from ::Taxonomy::Writer::ImmutableField do |error|
      render json: { error: "immutable_field", fields: error.fields }, status: :unprocessable_entity
    end

    # 409, not 422: nothing about the request was malformed — the node is
    # still load-bearing, and the counts say for whom.
    rescue_from ::Taxonomy::Writer::InUse do |error|
      render json: { error: "in_use", references: error.references }, status: :conflict
    end
  end
end
