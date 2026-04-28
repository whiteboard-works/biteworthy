include Rails.application.routes.url_helpers

class TagDatatable < ApplicationDatatable
  def_delegators :@view, :link_to, :image_tag

  def view_columns
    @view_columns ||= {
      name:        { source: "Tag.name" },
      description: { source: "Tag.description" },
      parent:      { source: "Tag.parent" },
      variety:     { source: "Tag.variety", searchable: false },
      icon:        { source: "Tag.icon_file_name", orderable: false },
      actions:     { source: "Tag.id", orderable: false, cond: :eq}
    }
  end

  def data
    records.map do |record|
      {
        name:        link_to(record.name, tag_path(record)),
        description: record.description,
        parent:      record.parent ? link_to(record.parent.name, admin_tag_path(record.parent)) : "",
        variety:     record.variety,
        icon:        image_tag(record.icon.url(:tiny), tooltip: record.name.tr("-", " ").capitalize, title: record.name.tr("-", " ").capitalize).html_safe,
        actions:     link_to('<i class="far fa-edit"></i>'.html_safe, edit_admin_tag_path(record), class: "action-icon") +
                     link_to('<i class="far fa-trash"></i>'.html_safe, admin_tag_path(record), class: "action-icon", method: :delete, data: { confirm: 'Are you sure?' })
      }
    end
  end

  private

  def get_raw_records
    Tag.all
  end

end
