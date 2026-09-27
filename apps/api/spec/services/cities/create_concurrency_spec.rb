require "rails_helper"

# Two admins adding the same city at once must not both pass the
# duplicate check and split its restaurants across two slugs. The
# advisory lock is the only thing preventing that, so this races two real
# connections through the check and holds each at the point where the
# race would happen: without the lock both read an empty table and both
# insert; with it the second waits, then sees the first city.
RSpec.describe Cities::Create do
  self.use_transactional_tests = false

  after { City.delete_all }

  it "creates the city once when two requests race" do
    arrived = 0
    mutex = Mutex.new
    allow(City).to receive(:order).and_wrap_original do |original, *args|
      rows = original.call(*args).to_a
      mutex.synchronize { arrived += 1 }
      deadline = Time.current + 0.5
      sleep 0.01 while mutex.synchronize { arrived } < 2 && Time.current < deadline
      rows
    end

    outcomes = Array.new(2) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          described_class.call(name: "Salt Lake City", region: "UT")
          :created
        rescue described_class::Duplicate
          :duplicate
        end
      end
    end.map(&:value)

    expect(outcomes).to contain_exactly(:created, :duplicate)
    expect(City.pluck(:slug)).to eq([ "salt-lake-city" ])
  end
end
