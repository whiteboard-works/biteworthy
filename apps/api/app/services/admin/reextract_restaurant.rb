# frozen_string_literal: true

module Admin
  # Start a fresh STAGED scan from a restaurant's latest inputs.
  # Does not auto-accept. Dry-run reports what would happen.
  class ReextractRestaurant
    Result = Struct.new(:ok, :error, :dry_run, :run, :input_count, :message, keyword_init: true)

    def self.call(restaurant:, dry_run: true)
      new(restaurant: restaurant, dry_run: dry_run).call
    end

    def initialize(restaurant:, dry_run:)
      @restaurant = restaurant
      @dry_run = dry_run
    end

    def call
      latest = @restaurant.ingestion_runs.order(created_at: :desc).first
      return fail_result("No ingestion runs found") unless latest
      return fail_result("No inputs attached to run #{latest.id}") unless latest.inputs.attached?

      blobs = latest.inputs.blobs.to_a
      user = latest.user
      return fail_result("Run #{latest.id} has no user") unless user

      if @dry_run
        return Result.new(
          ok: true,
          dry_run: true,
          input_count: blobs.size,
          message: "Would create a new scan from #{blobs.size} input(s) on run #{latest.id}"
        )
      end

      started = Ingestion::StartRun.call(user: user, restaurant: @restaurant, files: blobs)
      unless started.ok?
        return fail_result("StartRun failed: #{started.error}")
      end

      Result.new(
        ok: true,
        dry_run: false,
        run: started.run,
        input_count: blobs.size,
        message: "Started run #{started.run.id}"
      )
    end

    private

    def fail_result(message)
      Result.new(ok: false, dry_run: @dry_run, error: message, message: message)
    end
  end
end
