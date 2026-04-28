require 'test_helper'

class RestaurantMenuGroupsControllerTest < ActionController::TestCase
  setup do
    @restaurant_menu_group = restaurant_menu_groups(:one)
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:restaurant_menu_groups)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create restaurant_menu_group" do
    assert_difference('RestaurantMenuGroup.count') do
      post :create, restaurant_menu_group: { description: @restaurant_menu_group.description, name: @restaurant_menu_group.name, restaurant_id: @restaurant_menu_group.restaurant_id }
    end

    assert_redirected_to restaurant_menu_group_path(assigns(:restaurant_menu_group))
  end

  test "should show restaurant_menu_group" do
    get :show, id: @restaurant_menu_group
    assert_response :success
  end

  test "should get edit" do
    get :edit, id: @restaurant_menu_group
    assert_response :success
  end

  test "should update restaurant_menu_group" do
    patch :update, id: @restaurant_menu_group, restaurant_menu_group: { description: @restaurant_menu_group.description, name: @restaurant_menu_group.name, restaurant_id: @restaurant_menu_group.restaurant_id }
    assert_redirected_to restaurant_menu_group_path(assigns(:restaurant_menu_group))
  end

  test "should destroy restaurant_menu_group" do
    assert_difference('RestaurantMenuGroup.count', -1) do
      delete :destroy, id: @restaurant_menu_group
    end

    assert_redirected_to restaurant_menu_groups_path
  end
end
