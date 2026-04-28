class AddTitleAndCommentToReview < ActiveRecord::Migration
  def change
    add_column :reviews, :title, :string, after: :review_type
    add_column :reviews, :description, :text, after: :title
  end
end
