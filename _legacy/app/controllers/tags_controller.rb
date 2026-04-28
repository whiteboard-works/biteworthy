class TagsController < ApplicationController
  before_action :set_tag, only: [:show, :edit, :update, :destroy]

  def index
    @tags = Tag.joins(:items).order(name: :asc).uniq
  end

  def new
    @tag = Tag.new
  end

  def show

  end

  def edit
  end

  def create
    @tags = []
    tags = Tag.save_tags(tag_params[:name])
    tags.each do |tag|
      @tags << tag if tag.valid? && tag.save
    end
    if !@tags.empty?
      redirect_to tags_url, notice: 'Tag(s) successfully created.'
    else
      redirect_to new_tag_path, notice: 'Tag creation error.'
    end
  end

  def update
    if @tag.update(tag_params)
      redirect_to tags_url, notice: 'The tag was successfully updated.'
    else
      render action: 'edit'
    end
  end

  def destroy
    @tag.destroy
    redirect_to tags_url, notice: 'Tag was successfully deleted.'
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
    params.require(:tag).permit(:name)
  end
end
