class Avo::Filters::ReviewVisibility < Avo::Filters::SelectFilter
  self.name = "Visibility"

  def apply(_request, query, value)
    case value
    when "visible" then query.visible
    when "hidden"  then query.hidden
    else query
    end
  end

  def options
    { "" => "All", "visible" => "Visible", "hidden" => "Hidden" }
  end
end
