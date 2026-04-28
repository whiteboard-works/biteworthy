json.array!(@reports) do |report|
  json.extract! report, :id, :name, :description, :page_url, :report_type
  json.url report_url(report, format: :json)
end
