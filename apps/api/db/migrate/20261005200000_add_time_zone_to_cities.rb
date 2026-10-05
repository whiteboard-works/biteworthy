class AddTimeZoneToCities < ActiveRecord::Migration[8.0]
  # US state to IANA timezone mapping. Most states have one zone; states
  # spanning multiple zones get the most populous zone as the default.
  STATE_TIMEZONES = {
    "Alabama" => "America/Chicago",
    "Alaska" => "America/Anchorage",
    "Arizona" => "America/Phoenix",
    "Arkansas" => "America/Chicago",
    "California" => "America/Los_Angeles",
    "Colorado" => "America/Denver",
    "Connecticut" => "America/New_York",
    "Delaware" => "America/New_York",
    "District of Columbia" => "America/New_York",
    "Florida" => "America/New_York",
    "Georgia" => "America/New_York",
    "Hawaii" => "Pacific/Honolulu",
    "Idaho" => "America/Denver",
    "Illinois" => "America/Chicago",
    "Indiana" => "America/Indiana/Indianapolis",
    "Iowa" => "America/Chicago",
    "Kansas" => "America/Chicago",
    "Kentucky" => "America/New_York",
    "Louisiana" => "America/Chicago",
    "Maine" => "America/New_York",
    "Maryland" => "America/New_York",
    "Massachusetts" => "America/New_York",
    "Michigan" => "America/Detroit",
    "Minnesota" => "America/Chicago",
    "Mississippi" => "America/Chicago",
    "Missouri" => "America/Chicago",
    "Montana" => "America/Denver",
    "Nebraska" => "America/Chicago",
    "Nevada" => "America/Los_Angeles",
    "New Hampshire" => "America/New_York",
    "New Jersey" => "America/New_York",
    "New Mexico" => "America/Denver",
    "New York" => "America/New_York",
    "North Carolina" => "America/New_York",
    "North Dakota" => "America/Chicago",
    "Ohio" => "America/New_York",
    "Oklahoma" => "America/Chicago",
    "Oregon" => "America/Los_Angeles",
    "Pennsylvania" => "America/New_York",
    "Rhode Island" => "America/New_York",
    "South Carolina" => "America/New_York",
    "South Dakota" => "America/Chicago",
    "Tennessee" => "America/Chicago",
    "Texas" => "America/Chicago",
    "Utah" => "America/Denver",
    "Vermont" => "America/New_York",
    "Virginia" => "America/New_York",
    "Washington" => "America/Los_Angeles",
    "West Virginia" => "America/New_York",
    "Wisconsin" => "America/Chicago",
    "Wyoming" => "America/Denver",
    # Legacy state codes (some older rows may still have "CO" instead of "Colorado")
    "CO" => "America/Denver",
    "UT" => "America/Denver",
  }.freeze

  def up
    add_column :cities, :time_zone, :string

    # Backfill timezones for existing US cities based on their region
    City.where(country: "US").find_each do |city|
      tz = STATE_TIMEZONES[city.region]
      city.update_column(:time_zone, tz) if tz
    end
  end

  def down
    remove_column :cities, :time_zone
  end
end
