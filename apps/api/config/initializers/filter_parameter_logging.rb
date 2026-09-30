# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password)
# and filtered from the log file. Use this to limit dumping sensitive data
# into the logs. If a value contains any of the listed substrings, the whole
# value is filtered out.
Rails.application.config.filter_parameters += %i[
  passw secret token _key crypt salt certificate otp ssn
]

# Legal remediation E6 — the shareable profile token base64-encodes the
# sharer's avoid-lists + strictness (dietary data). Keep its value out of
# request logs. (`token` above already substring-matches `profile_token`,
# but list it explicitly so the intent is unmistakable.)
Rails.application.config.filter_parameters += %i[profile_token]

# The chat's "Use my location" coordinates arrive unrounded; the server
# coarsens them only after the request line is logged. Dotted so only
# these nested keys match, not every param with "lat" in its name.
Rails.application.config.filter_parameters += %w[
  context.location.lat context.location.lng context.location.accuracy_m
]
