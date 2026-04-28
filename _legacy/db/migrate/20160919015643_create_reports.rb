class CreateReports < ActiveRecord::Migration
  def change
    create_table :reports do |t|
      t.string :name
      t.text :description
      t.string :page_url
      t.integer :report_type

      t.timestamps null: false
    end
  end
end
