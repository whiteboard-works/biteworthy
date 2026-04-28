require 'rails_helper'

RSpec.describe "reports/index", type: :view do
  before(:each) do
    assign(:reports, [
      Report.create!(
        :name => "Name",
        :description => "Description",
        :page_url => "Page Url",
        :report_type => 2
      ),
      Report.create!(
        :name => "Name",
        :description => "Description",
        :page_url => "Page Url",
        :report_type => 2
      )
    ])
  end

  it "renders a list of reports" do
    render
    assert_select "tr>td", :text => "Name".to_s, :count => 2
    assert_select "tr>td", :text => "Description".to_s, :count => 2
    assert_select "tr>td", :text => "Page Url".to_s, :count => 2
    assert_select "tr>td", :text => 2.to_s, :count => 2
  end
end
