# Naming a conversation is a haiku call the loop makes on the first turn
# that finishes without a title — which, in a spec, is very nearly every
# turn. Left live it would hang a blocked HTTP request off each one:
# harmless, because `name_conversation` rescues, but it buys every chat
# spec a doomed round trip and a log line that is not about what is
# under test.
#
# The default is "the titler ran and declined to name it" rather than
# "the titler does not exist". Declining is a real outcome — a greeting
# has nothing to name — and it leaves `title` null, which is exactly what
# the column did before any of this. So every spec written before titles
# still describes what it always described.
#
# Specs that are *about* titling opt back in: `titled("...")` for the
# loop's side of it, `:real_titler` for the class's own spec.
module ChatTitlerStub
  def titled(title, usage: nil)
    allow(Chat::Titler).to receive(:new).and_return(fake_titler(title, usage: usage))
  end

  # `usage` defaults to nothing rather than to a plausible token count on
  # purpose: `record_side_usage` skips a blank one, so the default stub
  # adds no spend to any conversation. Specs that assert on cost or on
  # ceilings are counting the loop's own rounds, and a titler quietly
  # adding tokens to every one of them would be a spec breaking for a
  # reason that has nothing to do with what it describes.
  def fake_titler(title = nil, usage: nil)
    instance_double(
      Chat::Titler,
      call: Chat::Titler::Result.new(title: title, usage: usage, model: Chat::Titler::MODEL)
    )
  end
end

RSpec.configure do |config|
  config.include ChatTitlerStub

  config.before do |example|
    next if example.metadata[:real_titler]

    allow(Chat::Titler).to receive(:new).and_return(fake_titler)
  end
end
