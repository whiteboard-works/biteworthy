require 'rails_helper'

RSpec.describe "create_user_favorites/show", :type => :view do
  before(:each) do
    @create_user_favorite = assign(:create_user_favorite, CreateUserFavorite.create!(
      :is_liked => false,
      :metta_id => 1,
      :type_id => 2,
      :comment => "Comment"
    ))
  end

  it "renders attributes in <p>" do
    render
    expect(rendered).to match(/false/)
    expect(rendered).to match(/1/)
    expect(rendered).to match(/2/)
    expect(rendered).to match(/Comment/)
  end
end
