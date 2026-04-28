# Add your own tasks in files placed in lib/tasks ending in .rake,
# for example lib/tasks/capistrano.rake, and they will automatically be available to Rake.

require File.expand_path('../config/application', __FILE__)

Rails.application.load_tasks

namespace :one_time do
  task change_to_points: :environment do

    User.all.each do |user|
      Point.create(user_id: user.id, object_id: user.id, object_class: "User", change_type: Point.change_types["create_object"], worth: 42, object_changes: {custom: "New BiteWorthy member"}.to_json)
    end

    me = User.first
    user_classes = [Restaurant, Item, Food, Ingredient, Tag]
    user_classes.each do |uc|
      uc.all.each do |c|
        Point.create(user_id: me.id,
                     object_id: c.id,
                     object_class: c.class.to_s,
                     change_type: Point.change_types['create_object'],
                     worth: c.worth('create_object'),
                     object_changes: {custom: "Migration task"}.to_json)
      end
    end
    # TODO write migration to remove user_id from these tables
  end
end
