class DowncaseExistingUserHandles < ActiveRecord::Migration[8.1]
  # Handles became canonical-lowercase (model `normalizes :handle`), and
  # normalizes also downcases finder ARGUMENTS — so a pre-existing
  # mixed-case row (the old format regex was /i and signup always
  # permitted :handle) would become unfindable at /u/:handle under every
  # spelling. Downcase the stored rows to match the new invariant.
  def up
    # Straight downcase wherever the lowercase spelling is free.
    execute <<~SQL
      UPDATE users u
      SET handle = lower(handle)
      WHERE handle <> lower(handle)
        AND NOT EXISTS (
          SELECT 1 FROM users o
          WHERE o.id <> u.id AND lower(o.handle) = lower(u.handle)
        )
    SQL

    # Case-variant collisions (e.g. "Alice" alongside "alice" or
    # "ALICE") are genuinely ambiguous — no variant has a better claim
    # than the account already holding the lowercase spelling — so the
    # colliders fall back to the same neutral default a signup that
    # skipped the field gets.
    execute <<~SQL
      UPDATE users
      SET handle = 'diner_' || substr(md5(gen_random_uuid()::text), 1, 8)
      WHERE handle <> lower(handle)
    SQL
  end

  def down
    # The original casing is unrecoverable; the lowercase rows satisfy
    # every pre-migration constraint, so there is nothing to restore.
  end
end
