# L1 input — what chat actually sends to Anthropic

**Status:** input document for the L1 attorney review (see
`docs/plans/legal-remediation-followups.md` § B). Not a decision, not a draft
policy. It exists because the live Privacy Policy makes a statement about
Anthropic that the chat feature contradicts, and the attorney needs the real
data flows rather than the current copy.

**Written:** 2026-08-14, from the code at `1d8e21f6`. Every claim below cites a
file; re-verify before relying on it, because chat is under active development
(`docs/plans/chat-engine.md`).

---

## The problem in one line

`apps/web/src/app/privacy/page.tsx` tells users:

> **Anthropic**: when a menu is being ingested, the menu image is sent to
> Anthropic Claude for OCR + structuring. The image leaves our servers but is
> not used to train the model. **We do not send your reviews or profile to
> Anthropic.**

Both halves of that last sentence are false once chat is in play, and chat is
not mentioned anywhere in either legal document — `grep -ci chat` returns **0**
for `privacy/page.tsx` and **0** for `terms/page.tsx`.

The sentence was accurate when written: ingestion was the only Anthropic
surface. Chat arrived later and nobody revisited the copy.

---

## What is actually sent, per turn

`Chat::AgentLoop#model_args` (`apps/api/app/services/chat/agent_loop.rb:950`)
builds every request as `system` + `messages` + `tools`. Concretely:

### 1. The user's message text

Whatever they typed. Free-text, so it can contain anything they choose to
disclose — including, realistically, health details, since the product's whole
subject is what they cannot eat.

### 2. Their dietary profile, verbatim, in the system prompt

`Chat::SystemPrompt` (`apps/api/app/services/chat/system_prompt.rb:99-118`)
embeds a snapshot for every signed-in caller:

- Strictness setting
- **Avoided ingredients, by name**
- **Avoided tags, by name**
- Liked ingredients and tags
- Disliked ingredients and tags

This is the same data the E7 legal-remediation pass deliberately stripped out of
identified analytics events, on the reasoning (memo Issue 6) that associating a
health condition with an account is the existential privacy risk. That reasoning
is preserved in `packages/analytics/src/index.ts:85-99`. The chat path sends the
richer version of exactly that data to a third party on every turn.

The snapshot is a caching optimization — it saves a `get_profile` tool round
trip (`system_prompt.rb:21`). It is not required for correctness; the tools are
the source of truth.

### 3. The full conversation transcript

`cacheable(@conversation.transcript)` — the entire stored history replays on
every turn, not just the latest message.

### 4. Tool results, which can include review text

`Tools::Reviews::ListReviews` (`apps/api/app/services/tools/reviews/list_reviews.rb`)
returns review bodies into the model's context when called. So the "we do not
send your reviews" half fails too, conditionally on what the model does.

---

## What is retained

Every message persists to the `messages` table, joined to `conversations`.

The only deletion found in `Conversation` is `heal!`
(`apps/api/app/models/conversation.rb:194-197`), which removes empty assistant
messages so a crashed completion doesn't wedge the thread. **No TTL, no purge
job, no retention window** was found for chat transcripts — they appear to be
kept indefinitely, which the Privacy Policy's retention section does not cover
because it does not know chat exists.

Account deletion **does** cascade: `User has_many :conversations, dependent: :destroy`
(`apps/api/app/models/user.rb:37`) and `Conversation has_many :messages, dependent: :destroy`
(`conversation.rb:8`, likewise `runs` and `events`). So the deletion right is
honored in practice — it is only the *disclosure* that omits chat, not the
mechanism.

---

## Questions for the attorney

1. **Disclosure.** Chat needs its own entry in the Privacy Policy's
   third-party-services list and its own retention line. What level of
   specificity is required — "your messages and dietary profile" versus
   enumerating the fields?
2. **Special-category data.** The profile snapshot is health-adjacent by
   construction (celiac, allergy presets). Does sending it to a processor change
   the consent posture versus storing it ourselves? E7 treated this category as
   the thing to protect hardest.
3. **The false sentence.** It is live now. Does it need correcting ahead of the
   full L1 pass, or is the DRAFT banner sufficient cover in the interim?
4. **Retention.** Is indefinite transcript retention defensible, and does the
   deletion right in the CCPA section need to name chat explicitly?
5. **Anthropic's terms.** The ingestion copy asserts inputs are not used for
   training. Confirm that the same commitment covers the chat surface and that
   the API tier we are on actually carries it.

## Engineering options the answers might require

Listed so the attorney knows what is cheap and what is not — not as
recommendations:

- **Drop the profile snapshot from the system prompt.** Costs one `get_profile`
  round trip per turn that needs it; the tools already return the same data, so
  this narrows *when* profile data is sent rather than eliminating it.
- **Add a retention window** on `conversations` / `messages` with a purge job.
- **Cascade chat to account deletion**, if it does not already.
- **Correct the Anthropic bullet + add a chat section** to both documents.
