# frozen_string_literal: true

module Chat
  # Where the caller's device says they are, for one turn. Sent by the
  # client only while "Use my location" is on, and never stored past the
  # turn it rode in with: not on the profile, not in the transcript. The
  # model is told a location exists, never what it is; `search_restaurants`
  # reads it from the tool context, so coordinates cannot end up in a
  # tool_use block that is persisted with the conversation.
  module DeviceLocation
    # ~110 m. Enough for "nearest first" across a town; not a front door.
    PRECISION = 3
    MAX_ACCURACY_M = 50_000

    # Client-supplied, so anything malformed is dropped rather than
    # refused: a bad location should cost the sort, not the message.
    def self.from(raw)
      return nil unless raw.is_a?(Hash) || raw.is_a?(ActionController::Parameters)

      lat = number(raw[:lat] || raw["lat"])
      lng = number(raw[:lng] || raw["lng"])
      return nil if lat.nil? || lng.nil?
      return nil unless lat.between?(-90, 90) && lng.between?(-180, 180)

      accuracy = number(raw[:accuracy_m] || raw["accuracy_m"])
      {
        "lat" => lat.round(PRECISION),
        "lng" => lng.round(PRECISION),
        "accuracy_m" => accuracy && accuracy.positive? ? [ accuracy.round, MAX_ACCURACY_M ].min : nil
      }.compact
    end

    def self.number(value)
      return nil if value.nil? || value.is_a?(TrueClass) || value.is_a?(FalseClass)

      float = Float(value, exception: false)
      float&.finite? ? float : nil
    end
    private_class_method :number
  end
end
