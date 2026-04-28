class Admin::TagsController < AdminController
  before_action :set_tag, only: [:edit, :update, :destroy]

  def index
    respond_to do |format|
      format.html
      format.json { render json: TagDatatable.new(params, view_context: view_context) }
    end
  end

  def new
    @tag = Tag.new
  end

  def edit
  end

  def create
    tag = Tag.find_or_create_by(name: tag_params[:name])
    tag.update(tag_params)
    if tag.present?
      redirect_to admin_tags_path, notice: 'Tag successfully created.'
    else
      redirect_to new_admin_tag_path, notice: 'Tag creation error.'
    end
  end

  def update
    if @tag.update(tag_params)
      redirect_to admin_tags_path, notice: 'The tag was successfully updated.'
    else
      render action: 'edit'
    end
  end

  def destroy
    @tag.destroy
    redirect_to admin_tags_path, notice: 'Tag was successfully deleted.'
  end

  def add_child
    @child = Tag.find(params[:tag][:child_id])
    @parent = Tag.find(params[:tag][:id])
    @parent.add_child(@child)
    respond_to do |format|
      format.html { redirect_to edit_admin_tag_path(@child), notice: 'Tag was successfully linked.' }
      format.js { render "admin/tags/added_child" }
    end
  end

  def add_parent
    @child = Tag.find(params[:tag][:id])
    @parent = Tag.find(params[:tag][:parent_id])
    @parent.add_child(@child)
    respond_to do |format|
      format.html { redirect_to edit_admin_tag_path(@child), notice: 'Tag was successfully linked.' }
      format.js { render "admin/tags/added_parent" }
    end
  end

  def remove_parent
    @child = Tag.find(params[:id])
    notice  = if current_user.nom?
      @child.update(parent_id: nil)
      'Parent was successfully removed'
    else
      # TODO report attempted removal
      'You are not authorized for that action'
    end
    respond_to do |format|
      format.html { redirect_to edit_admin_tag_path(@child), notice: notice }
      format.js { render "admin/tags/added_parent" }
    end
  end

  private

  def set_tag
    @tag = if params[:id].to_i == 0
             Tag.find_by(name: params[:id])
           else
             Tag.find_by(id: params[:id])
           end
  end

  # Only allow a trusted parameter "white list" through.
  def tag_params
    params.require(:tag).permit(:name, :description, :variety, :icon)
  end
end
