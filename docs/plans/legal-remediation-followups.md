# Legal remediation — follow-ups

Tracking doc for work that surfaced **during** the Phase 2 engineering
remediation (E1–E13, all merged) but was intentionally deferred, plus
the Phase 3 attorney/ops items that can't be closed by code. Created
2026-06-14 after E1–E13 landed.

Phase 1 (privacy/ToS copy) and Phase 2 (E1–E13) are **done** — see
`docs/plans/archive/legal-remediation.md` for the full plan + the
legal↔code alignment matrix. This file is only the leftovers.

---

## A. Code follow-ups (in our control)

### F1 — Reword the analytics copy to the stronger "anonymous" promise `[COPY]`
E7c stripped the dietary fields (preset, strictness, avoid/hidden counts)
from the identified `profile_set` event, but the privacy + ToS analytics
sections still describe those fields being sent (the honest interim
wording from Phase 1). Now that they're gone, tighten the copy to state
that analytics never carry the dietary profile.
- Files: `apps/web/src/app/privacy/page.tsx` ("Your rights and controls"
  → analytics bullet), `apps/web/src/app/terms/page.tsx` ("Analytics").
- Deferred because Phase 1 owned those files and was unmerged while E7
  was in flight; both are on master now, so this is unblocked.

### F2 — Self-serve account deletion + data export UI `[ENG]`
E2 (`DELETE /api/v1/auth/signup`) and E3 (`GET /api/v1/account/export`)
shipped the **endpoints**, but there is no button that calls them — the
Privacy Policy still routes users to email `privacy@`. Add:
- Web: "Export my data" + "Delete account" actions on `/profile/settings`
  (the page E7a created), with a confirm step for delete.
- Mobile: the same in `Settings` (alongside the E7b analytics screen).
- Then update the Privacy Policy "Your rights and controls" copy from the
  manual email process to the in-app path, and **retire the manual
  `privacy@` fulfillment** once the UI ships (see F6).

### F3 — Per-user (not per-edge) API throttling `[ENG]`
E12's rack-attack throttles on `req.ip`. The web app proxies several
calls server-side (auth, profile, dmca, review mutations), so those reach
Rails from the Next server's IP — meaning web users share one bucket and
could trip the tight auth throttle together. Make throttling per-client:
- Forward `X-Forwarded-For` (original client IP) from the Next proxy
  routes under `apps/web/src/app/api/`.
- Trust it in Rails (`config.action_dispatch.trusted_proxies` / verify
  `ActionDispatch::RemoteIp` resolves the real client).
- Caveat is documented in `apps/api/config/initializers/rack_attack.rb`.

### F4 — Move the rack-attack counter to a shared store `[ENG]`
E12 uses a per-process `MemoryStore`, so throttle counts aren't shared
across Puma workers/processes. Switch to a shared store (Solid Cache or
Redis) when the API runs more than one process, or per-process buckets
let a client get N× the intended budget.

### F5 — True server-side signing for the share token `[ENG]` (low priority)
E6 added expiry + strict validation + log redaction to the `?p=` token,
but deliberately **did not** add an HMAC signature: the token is minted
client-side, so any secret would ship in the browser bundle and be
forgeable. If tamper-resistance is ever wanted, mint the token
server-side (a new endpoint) and sign it there. Low priority — the token
grants no privilege (only the sharer's own filter), so this is integrity,
not security.

### F6 — Retire the manual `privacy@` deletion/export process `[OPS]`
Once F2 ships the self-serve UI, the manual email-driven fulfillment that
Phase 1 committed to (Decision 4) is no longer the only path. Keep the
inbox for support, but the Privacy Policy should point at the in-app
controls as the primary route.

---

## B. Phase 3 — attorney / external (from legal-remediation.md)

These gate launch and cannot be closed by code. Restated here so the
follow-up list is complete; the canonical entries live in
`docs/plans/archive/legal-remediation.md` § Phase 3.

- **L1 — Licensed Colorado attorney review** of the finalized Privacy +
  ToS, including the warranty/liability/indemnity/arbitration clauses.
  Only after this do the **DRAFT banners** (and the source-file DRAFT
  comments on `privacy/page.tsx` + `terms/page.tsx`) come off. Launch gate.
  - **L1a — chat is undisclosed, and one sentence about it is false.**
    The Privacy Policy says "We do not send your reviews or profile to
    Anthropic"; `Chat::SystemPrompt` embeds the caller's strictness and
    named avoid-lists in every turn's system prompt, and
    `Tools::Reviews::ListReviews` can put review text in the context.
    Neither document mentions chat at all. Data flows, retention, and the
    questions for counsel are written up in
    [`chat-privacy-l1-brief.md`](./chat-privacy-l1-brief.md) — take that
    into the L1 pass. Found 2026-08-14 (#608).
- **L2 — Register a DMCA designated agent** with the U.S. Copyright
  Office (~$6) for §512 safe harbor, and stand up the repeat-infringer
  review process over the `dmca_notices` table that E10 created. Wire the
  agent contact into the ToS § Copyright + the `/dmca` page.
- **L3 — Attorney call on dish-photo cropping/rehosting**
  (`dish_photo_cropper.rb` rehosts cropped third-party menu photos on R2).
  Fair-use read is weak; likely move to a restaurant-upload / owner-opt-in
  photo model. Decision drives whether auto-crop ships at launch.
- **L4 — "BiteWorthy" trademark knockout search** + decide on the
  `LICENSE` file for the public repo.
- **L5 — Defer the "BiteWorthy-safe" badge** (endorsement liability) to
  the supply-side phase. Flag only; no work now.

---

## Sequencing

F1 and F2 are the highest-value (they finish making the privacy copy
true end-to-end and give users self-serve control). F3/F4 are
production-hardening for when the API scales. F5 is optional. L1 is the
true launch gate; L2/L3 should land before the corresponding features
(DMCA, dish-photo crop) are relied on publicly.
