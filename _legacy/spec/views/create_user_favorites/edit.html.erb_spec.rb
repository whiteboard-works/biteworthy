require 'rails_helper'

RSpec.describe "create_user_favorites/edit", :type => :view do
  before(:each) do
    @create_user_favorite = assign(:create_user_favorite, CreateUserFavorite.create!(
      :is_liked => false,
      :metta_id => 1,
      :type_id => 1,
      :comment => "MyString"
    ))
  end

  it "renders the edit create_user_favorite form" do
    render

    assert_select "form[action=?][method=?]", create_user_favorite_path(@create_user_favorite), "post" do

      assert_select "input#create_user_favorite_is_liked[name=?]", "create_user_favorite[is_liked]"

      assert_select "input#create_user_favorite_metta_id[name=?]", "create_user_favorite[metta_id]"

      assert_select "input#create_user_favorite_type_id[name=?]", "create_user_favorite[type_id]"

      assert_select "input#create_user_favorite_comment[name=?]", "create_user_favorite[comment]"
    end
  end
end
