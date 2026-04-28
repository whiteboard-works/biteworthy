require 'rails_helper'

RSpec.describe "create_user_favorites/new", :type => :view do
  before(:each) do
    assign(:create_user_favorite, CreateUserFavorite.new(
      :is_liked => false,
      :metta_id => 1,
      :type_id => 1,
      :comment => "MyString"
    ))
  end

  it "renders new create_user_favorite form" do
    render

    assert_select "form[action=?][method=?]", create_user_favorites_path, "post" do

      assert_select "input#create_user_favorite_is_liked[name=?]", "create_user_favorite[is_liked]"

      assert_select "input#create_user_favorite_metta_id[name=?]", "create_user_favorite[metta_id]"

      assert_select "input#create_user_favorite_type_id[name=?]", "create_user_favorite[type_id]"

      assert_select "input#create_user_favorite_comment[name=?]", "create_user_favorite[comment]"
    end
  end
end
