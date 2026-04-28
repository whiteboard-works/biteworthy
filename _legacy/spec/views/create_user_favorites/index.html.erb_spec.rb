require 'rails_helper'

RSpec.describe "create_user_favorites/index", :type => :view do
  before(:each) do
    assign(:create_user_favorites, [
      CreateUserFavorite.create!(
        :is_liked => false,
        :metta_id => 1,
        :type_id => 2,
        :comment => "Comment"
      ),
      CreateUserFavorite.create!(
        :is_liked => false,
        :metta_id => 1,
        :type_id => 2,
        :comment => "Comment"
      )
    ])
  end

  it "renders a list of create_user_favorites" do
    render
    assert_select "tr>td", :text => false.to_s, :count => 2
    assert_select "tr>td", :text => 1.to_s, :count => 2
    assert_select "tr>td", :text => 2.to_s, :count => 2
    assert_select "tr>td", :text => "Comment".to_s, :count => 2
  end
end
