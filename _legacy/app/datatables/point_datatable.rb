include Rails.application.routes.url_helpers

class PointDatatable < ApplicationDatatable
  def_delegators :@view, :link_to

  def view_columns
    @view_columns ||= {
      name:        { source: "Point.user_id" },
      object_class: { source: "Point.object_class" },
      object_id:     { source: "Point.object_id", searchable: false },
      change_type:     { source: "Point.change_type", searchable: false },
      worth:        { source: "Point.worth" },
      object_changes:     { source: "Point.object_changes", orderable: false },
      created_at:     { source: "Point.created_at", orderable: true },
      actions:     { source: "Point.id", orderable: false, cond: :eq }
    }
  end

  def data
    records.map do |record|
      actions = ""
      if record.change_type == 1  # Update
        actions = link_to("Revert", admin_revert_point_path(record))
      end

      {
        name:           record.user.user_name,
        object_class:   record.object_class,
        object_id:      record.object_id,
        change_type:    record.display_change_type,
        worth:          record.worth,
        object_changes: record.object_changes,
        created_at:     record.created_at.strftime("%Y-%m-%d %H:%M"),
        actions:        actions
      }
    end
  end

  private

  def get_raw_records
    Point.joins(:user).all.order(created_at: :desc)
  end

end
