require 'rails_helper'

RSpec.describe "reports/show", type: :view do
  before(:each) do
    @report = assign(:report, Report.create!(
      :name => "Name",
      :description => "Description",
      :page_url => "Page Url",
      :report_type => 2
    ))
  end

  it "renders attributes in <p>" do
    render
    expect(rendered).to match(/Name/)
    expect(rendered).to match(/Description/)
    expect(rendered).to match(/Page Url/)
    expect(rendered).to match(/2/)
  end
end
