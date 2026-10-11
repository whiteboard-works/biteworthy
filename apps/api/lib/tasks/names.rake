# frozen_string_literal: true

namespace :names do
  desc "Apply the naming standard to dishes saved before it existed (dry run unless DRY_RUN=false)"
  task normalize: :environment do
    dry_run = ENV["DRY_RUN"] != "false"
    scope   = ENV["RESTAURANT_ID"] ? Item.where(restaurant_id: ENV["RESTAURANT_ID"]) : Item.all

    puts "DRY RUN — pass DRY_RUN=false to write" if dry_run
    result = Names::Backfill.new(scope).call(dry_run: dry_run)

    result.changes.each do |change|
      change.before.each_key do |field|
        next if change.before[field] == change.after[field]

        puts "#{change.item.id} #{field}: #{change.before[field].inspect} → #{change.after[field].inspect}"
      end
    end
    puts "#{result.changes.size} item(s) #{dry_run ? 'would change' : 'changed'}"
    puts "#{result.stale} item(s) edited while running, left alone — run again" if result.stale.positive?
  end
end
