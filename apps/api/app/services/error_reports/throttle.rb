# frozen_string_literal: true

module ErrorReports
  # One queue insert per fingerprint per window, per process.
  #
  # A failure that fires on every request would otherwise queue a job per
  # request, and each of those jobs would do an upsert and a read to
  # learn that the hourly issue slot is already taken — load added to the
  # database and the workers at exactly the moment they are already
  # struggling. The first occurrence in a window goes through; the rest
  # are held and ride along as a count on the next one that does.
  #
  # Per process on purpose: no shared store means no shared-store call
  # on the failing path. Occurrences held when a burst ends are only
  # folded in by the next admission, so a burst's tail can go uncounted.
  # That is a few occurrences on a count that is already in the
  # hundreds, and the alternative is a timer thread in every process.
  class Throttle
    WINDOW   = 5
    MAX_KEYS = 1_000

    def self.shared
      @shared ||= new
    end

    def initialize
      @mutex = Mutex.new
      @seen  = {}
    end

    # The number of occurrences to enqueue now — this one plus any held
    # from the last window — or 0 when this one is folded into a window
    # that is still open.
    def admit(fingerprint, now: Process.clock_gettime(Process::CLOCK_MONOTONIC))
      @mutex.synchronize do
        prune(now) if @seen.size >= MAX_KEYS
        entry = @seen[fingerprint]
        if entry && now - entry[:at] < WINDOW
          entry[:held] += 1
          0
        else
          held = entry ? entry[:held] : 0
          @seen[fingerprint] = { at: now, held: 0 }
          held + 1
        end
      end
    end

    private

    def prune(now)
      @seen.delete_if { |_, entry| now - entry[:at] >= WINDOW && entry[:held].zero? }
      @seen.shift while @seen.size >= MAX_KEYS
    end
  end
end
