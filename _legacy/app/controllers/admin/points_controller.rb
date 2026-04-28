class Admin::PointsController < AdminController
  before_action :only_nom
  before_action :set_point, only: [:show, :edit, :update, :destroy, :revert_point]

  # GET /points
  # GET /points.json
  def index
    respond_to do |format|
      format.html
      format.json { render json: PointDatatable.new(params, view_context: view_context) }
    end
  end

  # GET /points/1
  # GET /points/1.json
  def show
  end

  # TODO skill point change/tracking
  def revert_point
    if current_user.is_admin? && current_user.nom?
      object_class = eval(@point.object_class)
      if(object_class.exists?(@point.object_id))
        @object = object_class.find(@point.object_id)
        changes = {}
        changes_json = JSON.parse @point.object_changes
        changes_json.keys.each do |change|
          changes[change] = changes_json[change].first
        end
        @object.update(changes)
        if @object.errors
          @notice = "Error: #{@object.errors.full_messages.to_sentence} for #{@point.object_class} with id #{@point.object_id}"
        else
          @notice = "REVERTED"
        end
      else
        @notice = "Could not find #{@point.object_class} with id #{@point.object_id}"
      end
    else
      @notice = "NOT ALLOWED"
    end
    redirect_to admin_points_path, notice: @notice
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_point
      @point = Point.find(params[:id])
    end


end
