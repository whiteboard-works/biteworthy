# Phase 6.4.1 — run-level moderation lens: ingestion runs created by
# non-admin users, so an admin can audit what the community scanned
# (the restaurant-level filter shows the OUTCOME; this shows the
# submissions, including failed/staged ones that never published).
class Avo::Filters::CommunityRuns < Avo::Filters::BooleanFilter
  self.name = "Community runs"

  def apply(_request, query, value)
    return query unless value[:community]
    query.joins(:user).where(users: { is_admin: false })
  end

  def options
    { community: "Created by a non-admin user" }
  end
end
