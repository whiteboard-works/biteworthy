class Avo::Filters::AwaitingModeration < Avo::Filters::BooleanFilter
  self.name = "Awaiting moderation"

  def apply(_request, query, value)
    return query unless value[:flagged]
    query.awaiting_moderation
  end

  def options
    { flagged: "Flagged by spam heuristic" }
  end
end
