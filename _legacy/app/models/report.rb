class Report < ActiveRecord::Base

  validates :name, :description, :page_url, :report_type, presence: true

  enum report_type: [ :bug, :idea, :observation, :other ]

end
