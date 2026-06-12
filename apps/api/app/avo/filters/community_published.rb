# Phase 6.4 — the admin's moderation lens over community-created
# restaurants. Doesn't gate anything (community publishes go live per
# the Phase 6.3 trust model); this is how an admin SEES what the
# community shipped so the confirm-all action can graduate it.
class Avo::Filters::CommunityPublished < Avo::Filters::BooleanFilter
  self.name = "Community published"

  def apply(_request, query, value)
    return query unless value[:community]
    query.community_published
  end

  def options
    { community: "Created by a community member and live" }
  end
end
