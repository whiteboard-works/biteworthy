class MenuGroupsController < ApplicationController
  before_action :set_menu_group, only: [:show]

  respond_to :html

  def index
    @menu_groups = MenuGroup.all
    respond_with(@menu_groups)
  end

  def show
    respond_with(@menu_group)
  end

  private
    def set_menu_group
      @menu_group = MenuGroup.find(params[:id])
    end
end
