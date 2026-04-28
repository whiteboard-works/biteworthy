class CreatePrices < ActiveRecord::Migration
   def change
    create_table :prices do |t|
      t.integer  :priced_id
      t.string   :priced_type
       t.float   :value
       t.string  :size
    end
  end
end
