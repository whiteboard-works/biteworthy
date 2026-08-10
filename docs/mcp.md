# The MCP tool layer

The tool layer is the primary design surface for Biteworthy's domain
operations. Each tool is reachable two ways — over MCP at `POST /mcp`, and
(from Phase 3) from the first-party chat's agent loop — so authorization,
validation, and result shaping live in the tool and nowhere else.

MCP does **not** replace the REST API. `apps/web` and `apps/mobile` can't
speak it. The end state is one command layer with two adapters over it:
MCP tool classes and thin REST controllers.

```
        apps/web (light UI + chat)          Claude Desktop / Claude Code
                    │                                    │
          REST  ────┤                                    │  MCP
                    ▼                                    ▼
      app/controllers/api/v1/*            app/controllers/mcp_controller.rb
                    │                                    │
                    └──────────────┬─────────────────────┘
                                   ▼
                        app/services/tools/
                                   │
                                   ▼
              models · app/services/menus/* · app/services/ingestion/*
```

## Where things live

| Path | What |
|---|---|
| `app/services/tools/base.rb` | `Tools::Base` — audience enforcement, error translation, `ok`/`error`, untrusted-content fencing |
| `app/services/tools/context.rb` | Who is calling, resolved from the MCP `server_context` |
| `app/services/tools/errors.rb` | Domain errors that become `isError` results rather than protocol errors |
| `app/services/tools/registry.rb` | The catalog; `Registry.for(context)` filters by audience and scope |
| `app/services/tools/instructions.rb` | Server instructions — also the chat's system prompt |
| `app/services/tools/topology.rb` | Which tools compose into which workflow |
| `app/services/tools/topology_resource.rb` | The same map as `biteworthy://topology` |
| `app/services/tools/meta/` | `describe_capabilities`, for clients that don't read resources |
| `app/services/tools/discovery/` | Public read tools |
| `app/services/tools/profile/` | The caller's own avoid lists, strictness, saves |
| `app/services/tools/ingestion/` | Menu scanning; run-scoped, signed-in |
| `app/services/tools/reviews/` | Per-dish reviews. Reading is public, writing is not |
| `app/services/tools/suggestions/` | The correction queue; owner- or admin-gated to resolve |
| `app/services/tools/claims/` | Restaurant ownership, by emailed token |
| `app/services/tools/history/` | The caller's own visits and saves |
| `app/services/tools/restaurants/` | Adding, editing, and verifying a restaurant |
| `app/services/tools/admin_base.rb` | `Tools::AdminBase` — the one place `audience :admin` is declared |
| `app/services/tools/structure/` | Menus, sections, address, hours (admin) |
| `app/services/tools/items/` | Deep-editing a live dish (admin) |
| `app/services/tools/taxonomy/` | The ingredient and tag trees (admin) |
| `app/services/tools/moderation/` | The review queue (admin) |
| `app/services/tools/users/` | The roster and the admin bit (admin) |
| `app/controllers/mcp_controller.rb` | Transport adapter. No domain logic |

`Registry::DOMAINS` is the catalog. A tool that isn't in it doesn't exist —
`Registry.all` is built from it, and `registry_spec.rb` fails if any tool
lands outside a domain.

Tools live under `app/services/` rather than `app/tools/` because Zeitwerk
makes every direct subdirectory of `app/` an autoload root — `app/tools/base.rb`
would have to define top-level `Base`, not `Tools::Base`.

## Writing a tool

Subclass `Tools::Base` and implement `self.perform`, not `self.call`:

```ruby
module Tools
  module Discovery
    class GetRestaurant < Tools::Base
      audience :public          # :public | :user | :admin

      tool_name  "get_restaurant"
      title      "Get restaurant details"
      description "…what it does, when to call it, what the fields mean…"

      input_schema(properties: { restaurant: { type: "string" } }, required: ["restaurant"])
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true)

      def self.perform(context:, restaurant:)
        ok(id: …, name: …)
      end
    end
  end
end
```

Then add it to `Tools::Registry.all`.

Notes that bite:

- **Descriptions are the interface.** The model decides whether to call a
  tool almost entirely from its description. Say *when* to call it and what
  the fields mean, not just what it does.
- **`audience` and scope both gate visibility, not just access.**
  `Registry.for(context)` drops tools the caller may not use, so a
  non-admin's `tools/list` never mentions the admin tools and a read-only
  token's never mentions the writes. `Tools::Base` re-checks at call time
  as defence in depth. One consequence to expect: a call to a tool the
  caller cannot see comes back as "tool not found" rather than a scope
  complaint, because it was never in that caller's catalogue.
- **Raise `Errors::NotFound` / `Errors::InvalidArgument`**, don't return
  error hashes. `Base.call` turns them into `isError` results the model can
  recover from. An unexpected exception is contained too, but as
  `tool_failed` — a bug must not look like a recoverable domain error, or
  the model rewrites its arguments and calls the broken tool forever.
  **Nothing escapes `Base.call`**, through either front door; that is what
  let the chat loop drop its own rescue.
- **Arguments are validated before `perform` runs**, against both the
  declared `input_schema` and the real Ruby signature — the schema knows
  types and required-ness, only the signature knows which keywords
  `perform` will accept. All problems are reported in one message so a
  model with two mistakes fixes both in one round.
- **If `perform` takes `**args`, declare `additionalProperties: false`.**
  An open signature cannot tell a real keyword from an invented one, so the
  schema has to. The six admin multiplexers (`edit_item`,
  `edit_menu_structure`, …) all do.
- **Fence extracted text with `untrusted(...)`.** Dish names and
  descriptions came from strangers' photos and scraped pages.
- **Take slugs, not UUIDs**, on write tools. Models handle slugs reliably
  and `search_taxonomy` resolves them.
- **`audience` is inherited through the superclass chain.** A domain base
  class can declare it once (`Tools::Ingestion::Base` is `:user`). This is
  deliberate plumbing — Ruby does not inherit class-level ivars, and the
  naive version left every subclass at the `:public` default.
- **Declare `running_description`** on anything a person watches. It is the
  only text a user reads while a turn works, and it is the tool's to write —
  never the model's.
- **`confirm_when` is enforced by `Base.call`, on both doors.**
  `destructive_hint` is static, so an MCP client reads it and puts a human
  in front of the call itself; `confirm_when` covers the case no annotation
  can express — a tool that is dangerous only for certain arguments.
  `update_avoid_lists` is the reason it exists: it declares
  `destructive_hint: false` so *adding* an avoid stays frictionless, which
  tells every client the call is safe, and it is — until the arguments say
  `remove_ingredients`. Only the server knows that, so only the server can
  ask. A gated call with no grant comes back as `confirmation_required`
  carrying the declared sentence and a `confirmation_token`; the caller
  asks, then repeats the call with `confirmation:`. The grant is bound to
  a digest of the tool, the arguments, and the caller (`Tools::Confirmation`,
  10-minute TTL), so an approval to stop avoiding peanut cannot be replayed
  against peanut *and shellfish*, or against someone else's profile. The
  chat parks before it gets there and mints a grant once the person taps
  approve — one check, not a pre-check here and a different one over MCP,
  which is how this gate came to guard only the chat for a while.

  **What the server enforces is the protocol, not the human.** The refusal
  hands the token to the same caller it just refused, because over a
  stateless transport there is nowhere else to send it — no elicitation, no
  socket back to the person. A client that never asks anyone satisfies the
  gate by calling twice. What is actually bought: the question is
  server-authored rather than composed by the model asking for a yes, it
  cannot be answered for a *different* call than the one described, and a
  client that does put a human in front of it has an exact sentence to
  show. A client that does not is not stopped, and cannot be from here.

  A grant has no nonce, so it is reusable for its whole TTL — which means a
  gated tool must be idempotent. `confirmation_gate_spec` asserts that over
  the real registry rather than trusting it.
- **`unrecoverable_when` is the chat's `accept_edits` line, and nothing
  else reads it.** `destructive_hint` is a wide net — every write that
  changes stored data, which puts `edit_item` beside `delete_taxonomy_node`.
  That width is right for "should a human see this once" and useless for
  "may a standing grant cover this". The narrower question is
  recoverability: a menu edited wrong is fixed by editing it again; a
  deleted taxonomy node, a deleted review, and a granted admin role are
  not. It takes a block rather than a flag because the answer is often
  argument-dependent — `edit_menu_structure` creates, renames, and
  deletes through one tool, and `resolve_suggestion` is unrecoverable
  only for `accepted`.

  **Every `destructive_hint` tool must declare it, either way**, and
  `registry_spec` fails the build otherwise. `accept_edits` parks an
  undeclared destructive tool rather than running it, so the default
  fails closed — that inversion is not decoration. The first cut defaulted
  to "recoverable", and two separate review passes each found a tool
  being waved through on it: `resolve_suggestion` (applying a *stranger's*
  correction, where an accepted `remove_ingredient` un-hides a dish for
  everyone avoiding the ingredient) and `confirm_restaurant_data` (whose
  own description says "cannot be undone" and whose whole purpose is
  making dishes visible to strict-mode users — people filtering for a
  real allergy). Neither author did anything wrong; the default was.
  Write `unrecoverable_when { false }` to say a destructive tool really
  is an ordinary edit.

  **`update_avoid_lists` deliberately does not declare it.** A removal is
  still gated in `manual`, and `accept_edits` waves it through — which is
  a real loosening of Safety Property 5, chosen knowingly so that a
  profile-editing session is not interrupted twice a minute. The mode's
  own copy says so in both clients rather than promising only "asks
  before a delete"; if that trade is ever revisited, the declaration is a
  one-liner.
- **New tools are deferred by default in the chat.** Only the core domains
  (discovery, profile, meta) stay resident; everything else loads on demand
  via tool search, which is what keeps a cold turn from carrying 13k tokens
  of schema. Add a domain to `Chat::ToolCatalog::CORE_DOMAINS` only if it
  genuinely opens conversations.
- **Don't block a tool call on a slow LLM call.** Extraction runs in a job
  and `start_menu_scan` returns a scan id for the caller to poll. A tool
  that blocks for a minute times out real clients.

## Workflow prompts

The same workflows are offered over MCP as **prompts** — things a person
picks in Claude Desktop before typing anything. "Scan a menu into the
database" is a better starting point than a blank box and forty-four
tools.

`Tools::WorkflowPrompts` **generates** them from `Topology::WORKFLOWS`;
nothing is restated. A prompt that drifted from the topology would be
documentation lying to a model at runtime, which is the failure the
topology spec exists to prevent. Adding a workflow gets a prompt for free.

Audience-filtered like everything else: a workflow is offered only to a
caller who can run every step, so `prompts/list` never suggests a route
that dead-ends in `forbidden`.

### Argument completion

A workflow declares `arguments:` (`restaurant`, `city`, `avoid`) on the
same constant, and `Tools::Completions` answers `completion/complete` for
them — so the box a client draws and the thing that can fill it come from
one place. All arguments are optional: a workflow has to stay pickable by
someone who does not yet know which restaurant they mean.

This is worth more here than it looks. Every write path takes a **slug**,
and slugs are the one thing nobody can guess — `search_taxonomy` exists
because a model cannot turn "garbanzo" into `chickpea`. A person filling in
a prompt argument had the same problem and a blank box; the gem's default
handler answers every completion with an empty list.

Three properties, each pinned:

- **Every source is public data.** Completions run before any tool call and
  carry no scope of their own, so a suggestion list is a read even when it
  looks like a hint. Restaurants are filtered to `published` — an
  unpublished one appearing here would announce a draft to anyone who typed
  two letters.
- **Prefix, not substring.** A slug is a name someone is part-way through
  typing; matching the middle turns "cafe" into every restaurant containing
  the word. `%` and `_` are sanitized — they are characters someone typed,
  not a pattern they meant.
- **The prompt in `ref` resolves against this caller's own filtered list**,
  so a workflow they cannot run cannot be completed against either. That
  falls out of `WorkflowPrompts.for` rather than being a second rule here.

### The menu as a resource

`biteworthy://restaurant/{restaurant}/menu` (`Tools::MenuResource`) is a
resource **template**, so a person can attach a menu the way they attach a
file rather than hoping the model reaches for `get_menu`. Different job
from the tool, not a second copy of it: a tool is what the model calls
mid-answer, a resource is what a human picks before typing — the right
shape for "here are two menus, help me choose".

**The filter applies, and hidden dishes stay in.** That is what makes it
safe to be a resource at all. The attachment is not "the menu", it is
*this reader's* menu, with every dish they cannot eat still present under
"Cannot eat, and why". Dropping them would be a quieter lie than the tool
could tell, because there is no tool call for anyone to question. It reads
`Menus::Query`, so there is one filter underneath both surfaces.

Dish text is fenced with `Tools::Untrusted.fence` — its own module now,
because two surfaces emit extracted text and a fencing convention each
surface spells for itself eventually gets spelled differently. The
template variable is named `restaurant`, the same argument the prompts
use, so one completion vocabulary serves both.

**`listChanged` is deliberately not advertised.** It promises a
`notifications/*/list_changed` when the catalogue changes, and a stateless
transport has no channel to send one on. The gem defaults it to true, so
until the capabilities were declared explicitly every client was told to
expect a message that could never arrive — and these lists genuinely do
change per caller, which is what made the claim worth removing rather than
ignoring.

## The topology

Forty-four tool descriptions say what each call means in isolation. They do
not say that fixing a wrong ingredient is `explain_item` → `search_taxonomy`
→ `suggest_correction` → somebody else resolving it, or that
`accept_staged_items` is the only step in the whole scan flow that publishes
anything. `Tools::Topology` holds that composition and ships on two surfaces:

- **`biteworthy://topology`** — an MCP resource, `text/markdown`, so a client
  that reads resources gets the map without spending a turn on a tool call.
- **`describe_capabilities`** — the same content as a tool, for a bare
  Messages-API loop that has no resource support.

Both filter by audience the way `Registry.for` does: a workflow is offered
only to a caller who can run **every** step. Otherwise the map advertises a
route that dead-ends in `forbidden` halfway through.

Each workflow declares its own audience, and `topology_spec.rb` asserts that
declaration really does cover every step — so adding an admin tool to a
`:user` workflow fails the suite rather than shipping a plan that breaks on
step three. It also asserts every named tool exists, which is what keeps this
from becoming documentation that lies.

## The ingestion flow

Verification is a conversation. The path is:

```
start_menu_scan   →  get_scan_status (poll until ready)
                  →  list_staged_items  [needs_attention: true]
                  →  edit_staged_item   (fix what didn't resolve)
                  →  accept_staged_items  ← the only step that publishes
                  →  undo_staged_item   (if that was wrong)
```

Two properties the tools enforce rather than trust the model with:

- **Run scoping.** Every ingestion tool resolves the run and checks the
  caller owns it, or is an admin. Someone else's scan is `not_found`, not
  `forbidden` — "you may not touch scan X" confirms scan X exists.
- **Nothing publishes except accept.** Scanning, listing, and editing all
  stay in staging. `accept_staged_items` carries
  `destructive_hint: true` so a client that surfaces annotations prompts
  before calling it.

## The correction flow

The other way live menu data changes. Same shape — propose, then a
privileged party applies:

```
suggest_correction   (anyone, signed in or not; queues, changes nothing)
                  →  list_suggestions   (owner or admin only)
                  →  resolve_suggestion (accept APPLIES it to the live dish)
```

The gate is `claimed_by_user_id` on the restaurant, set by
`claim_restaurant` → emailed token → `verify_claim`. Admins pass it too.

`suggest_correction` is the one write in the whole surface with
`audience :public`, and that is deliberate rather than an oversight.
`POST /api/v1/items/:id/suggestions` has taken anonymous corrections
since Phase 4.10 — someone who spots that a dish has cilantro should not
need an account to say so — and the same act being allowed on one door
and refused on the other is exactly the divergence this layer exists to
prevent. It queues; it changes nothing; an anonymous row lands with
`user_id: nil` and a `submitter` the serializer omits. The cost is a
reviewer's attention, and `/mcp` has carried a 30/minute anonymous
ceiling since #550.

Accepting `remove_ingredient` deletes a join row, which un-hides that dish
for everyone avoiding the ingredient — the most dangerous write available
to a non-admin, which is why it carries `destructive_hint: true` and the
server instructions tell the model to say what accepting would change.

## The admin surface

Everything under `audience :admin` descends from `Tools::AdminBase`, which
is the only place that audience is declared. `Registry.for(context)` drops
them wholesale for non-admins, so a normal caller's `tools/list` never
mentions them.

### Deleting things

`DELETE /api/v1/admin/<resource>/:id` means **archive**;
`?hard=true` means the row is gone, and is super-admin only (a plain admin
gets the same 404 `require_admin!` gives a non-admin, so the response never
confirms the capability exists). The rule lives once, in
`Api::V1::Admin::Deletable`.

Only **restaurants** and **ingestion runs** archive — they are the two with
no tombstone of their own, so they got `archived_at`. Items, reviews and
suggestions already had one before this existed (`status: "removed"`,
`hidden_at`, `status: "rejected"`), and reaching those through `DELETE`
would mean inventing a value to write: `Review#hide!` takes a reason from a
closed list of *editorial* judgments, and a delete button recording "spam"
because the enum had nothing better would put a false reason in a
moderation audit trail. A bare `DELETE` on those three returns a 422 naming
the endpoint that does it properly. Users have no archive at all — the app
has no deactivated-account state.

Restaurant claims are suggestions (`RestaurantClaim` writes one), so the
suggestion delete is the claim delete.

**A hard delete is only as complete as the model's `dependent:` list.** Every
foreign key into these tables is a plain `REFERENCES` with no `ON DELETE`, so
anything Ruby forgets arrives as a 500 rather than a refusal — and
`suggestions.subject` is polymorphic, so it has no foreign key to forget
*with*. `spec/models/hard_delete_cascade_spec.rb` builds the full graph and
destroys it, which is where a new FK without a matching association gets
caught.

**The archive is honoured by one line, not thirty.** `Restaurant.published`
is the chokepoint every public read already goes through — list, detail,
menu, reviews, suggestions, the chat discovery tools, and
`Cities::RestaurantRanking` — so `scope :published, -> { kept.where(…) }`
covers all of them at once. Exactly two readers bypass it, both on purpose:
the saved-restaurant lists show draft and closed restaurants so the page can
grey out the link, and they filter on `kept` themselves.
Exactly **three** readers bypass it, all on purpose: the saved-restaurant
list, the saved-dish list, and browsing history all show draft and closed
restaurants so the page can grey out the link, and each filters `kept`
itself. `spec/requests/admin/archive_visibility_spec.rb` names every reader
individually, so a future one that queries around `published` fails there
rather than quietly serving an archived restaurant.

Two things the archive deliberately does **not** do. It does not free the
slug — `restaurants.slug` is unique across archived rows too, so re-creating
an archived restaurant under its old slug needs the hard delete. And it does
not change `status`, which is why the three bypassing readers filter on
`kept` rather than on status: an archived restaurant still reports
`status: "published"`.

On the web side the same rule lives in two components:
`_HardDeleteButton` (a two-step confirm that **renders nothing** below
the super tier) and `_TypeToConfirm` (retype the name, reserved for the
two deletes that take other records with them — a restaurant and a user
account). The tier reaches them through `AdminTierProvider`, filled from
the `/me` call the admin layout already makes for its guard. That is UI
gating, not the gate: Rails answers `?hard=true` with a 404 regardless.
It exists because the repo's promote/demote toggle set the rule that a
button which always fails is worse than no button — and because a 404
rendered as "your admin access is gone" would send an operator who
merely lacks a tier to sign in again, which fixes nothing.

Taxonomy is the exception to the tier: `Taxonomy::Writer#destroy!` refuses
to delete a node someone has in an avoid list, and a super admin gets that
refusal too. A force that ignored it would silently weaken a live allergen
filter.

### The super tier

`users.is_super_admin` sits above `is_admin` and lifts the limits, not the
permissions: the per-conversation and daily chat spend ceilings, the
tool-round cap (12 → 60), the ingestion input-size caps (5×), and every
`Rack::Attack` throttle. It grants **no additional tools** — the audience
filter is unchanged, because `super_admin_implies_admin` (a CHECK
constraint) guarantees a super admin is already an admin, so every
existing `is_admin?` call site and every `.where(is_admin: …)` scope keeps
working untouched.

The one capability it does add is not a tool: **irreversible delete**, over
REST only (see below). Deliberate — the tools are what a model drives, and
`DROP the row` is the operation with no undo.

Two properties are the whole design, and both are asserted by specs:

- **It is granted from a shell and nowhere else** — `admin:grant_super`
  / `SUPER_ADMIN_EMAILS` via `Biteworthy::AdminRoster`. In production the
  roster has to be in **two** places: a value in `.kamal/secrets` and the
  variable's name in `config/deploy.yml`'s `env.secret:` list, which is
  what actually puts it in the container. Missing the second is a loud
  failure rather than a dangerous one — `admin:sync_super` aborts on a
  blank roster, and both sync tasks only ever grant, so a typo cannot
  demote the one operator who could still fix it. `set_user_role`
  and `PATCH /admin/users/:id` cannot set it, and both refuse to *demote*
  an account that has it. Any admin can promote another admin, so if
  plain admin cleared the spend ceilings, one promotion would hand out an
  uncapped Anthropic bill; keeping the grant on the shell side makes the
  set of people who can spend without a ceiling equal to the set of
  people with server access.
- **The throttle exemption verifies the credential, never reads it.**
  `Biteworthy::SuperAdminCredential` signature-checks a Devise JWT (and
  compares `jti`, because `JTIMatcher` revokes by rotating it), digest-
  looks-up an `bw_mcp_` token, or resolves a Doorkeeper access token,
  caching the decision for 60s against a hash of the secret. The tempting
  version — base64-decode the JWT and trust `sub`, which is what the web
  app's `getServerUserId` does for UI purposes — would let anyone opt out
  of every rate limit by claiming an id. Every error path returns false.
- **Resolution is itself rate limited, per IP, on cache misses only.** A
  safelist runs ahead of every throttle, so without a bound it is an
  amplifier: a unique garbage bearer per request misses the cache by
  construction and forces a credential lookup nothing is limiting. Ten
  resolutions per IP per minute is far more than a real caller needs
  (they resolve once a minute and the cache answers the rest) and turns a
  spray of forged bearers into a few lookups followed by the ordinary
  throttles they were trying to skip.

`skip_confirmations` is a separate column, defaulting on for the tier but
independently settable. It turns off the destructive-tool confirmation
gate — including an avoid-list *removal*, which un-hides dishes and is
the one direction that can hurt somebody (Safety Property 5 in
`docs/plans/chat-engine.md`). Both halves of the gate honour it: the chat
parks before the tool boundary is reached, so `Chat::ModePolicy` (via
`AgentLoop#decide`) and `Tools::Base#confirmation_gate` each check it, and
missing either one strands the turn waiting for an answer the other would
have waved through. It is a standing answer to the *confirmation* question
only — planning mode still refuses writes for a super admin, because that
is a scope for the turn rather than a question being asked.

**Raised rather than lifted: the wall-clock turn deadline** (300s →
1,800s) **and the ingestion input caps** (5×). Both are bounds on damage
rather than permissions, and both re-admit a smaller version of the
problem they guard when raised — which is the honest reading, not a
technicality. The deadline: a wedged turn keeps `tick!` renewing its 120s
lease, so it reads healthy to every watchdog for as long as the deadline
allows; 30 minutes is acceptable only because the lock is **per
conversation** and the operator holding it has `DELETE
/conversations/:id/run`.

**Not multiplied per-user: `MAX_TOTAL_INPUT_BYTES` (20 MB).** Multiplying
the file count and the per-file size independently multiplies their
product — 5× × 5× is 25× in aggregate, which turned a 100 MB ceiling into
2.5 GB. `ExtractMenuPrompt.user_messages` base64-encodes every blob into
one in-memory request, so that is gigabytes built in the worker before
Anthropic rejects it for exceeding the 32 MB request limit: the same
discovered-too-late failure that keeps the content-type check
unskippable. This ceiling is about what the API accepts, not about who is
paying, so it binds a super admin exactly as hard (it is still
operator-tunable through `INGESTION_MAX_TOTAL_INPUT_BYTES` — what it does
not do is scale with the caller). Chunking is what would let it rise,
because the aggregate would no longer be one request.

Two consequences worth stating rather than discovering. It **clamps the
per-file ceiling**, so the tier's nominal 50 MB single file is really
20 MB — real headroom over the ordinary 10 MB, just not five times it.
And it is **a tightening for ordinary callers too**: ten files at 10 MB
used to be a nominal 100 MB batch. Nothing could ever have extracted
that, so the change is the door refusing what the extractor was going to
reject anyway — but it is a behaviour change for everyone, not only the
new tier. `StartRun.per_file_byte_limit` is the one owner of that
arithmetic, shared with `AttachmentsController` so the upload door and
the scan door cannot answer differently; they already had, and the tier's
per-file headroom was unreachable through the door the chat uses.

Three rails carry over from the admin REST endpoints, and they are the
reason these tools are narrower than the models allow:

- **`items.confidence` is not settable.** It moves only through
  `promote!` and `confirm_restaurant_data`, because strict-mode
  visibility rides on it. `edit_item` writes joins, never the item's own
  confidence.
- **Taxonomy `slug`, `path`, and a tag's `family` are immutable.**
  Ingestion resolves by slug at promote time, so a rename silently drops
  joins; an ltree path move orphans every descendant. Neither cascades.
- **A taxonomy node in use cannot be deleted.** `delete_taxonomy_node`
  counts descendants, item joins, dietary presets, add-ons, and user
  profiles first. A node sitting in somebody's avoid list would vanish
  from their filter silently — profiles tolerate ids that no longer
  resolve.

`edit_place`, `edit_item`, and the three `*_taxonomy_node` tools share
their validation with the REST controllers rather than reimplementing it:
`Places::Writer`, `Admin::ItemEditor`, and `Taxonomy::Writer`
respectively. That is deliberate — the place/item writers validate before
coercing, because Rails' casts are lossy in exactly the directions that
corrupt live data (`"monday".to_i` is `0`, `"25:99"` becomes "closed", a
non-numeric latitude becomes Null Island), and `Taxonomy::Writer` exists
because the alternative was already demonstrated: the two admin
controllers and `Tools::Taxonomy::Base` each owned a copy of the rules,
and only the tag controller counted `prefer_tag_ids` as a reference, so
one tag was undeletable over REST and deletable over MCP.

## The first-party chat

`Chat::AgentLoop` is the second front door: the same registry, the same
audience filter, the same server instructions, driven against
`claude-opus-5` with adaptive thinking. `Chat::ToolCatalog` renders the
MCP tool classes as Messages API tool definitions — one registry, two
wire formats, never two implementations.

Four things it enforces that a bare tool loop would not:

- **Confirmation before a destructive call.** The loop stops at the first
  tool whose `destructive_hint` is true, or whose `confirm_when` trips on
  the actual arguments, and parks it in `conversations.pending_tool_call`.
  Nothing that publishes, deletes, or changes what a person is shown runs
  because a model decided to. Each such call needs its own answer, so a
  queue of them parks one at a time — confirming one does not pre-authorize
  the next. On approval the loop mints a `Tools::Confirmation` grant and
  passes it to the tool, because `Base.call` re-checks the argument-gated
  half itself — see §"Writing a tool".

  **How much of that a person has agreed to up front is the turn's
  mode.** `Chat::ModePolicy` answers `:run` / `:park` / `:refuse` for one
  call, and `conversations.chat_mode` is the four-value column behind it:

  | mode | what runs | what stops |
  | --- | --- | --- |
  | `planning` | `read_only_hint: true` only | every write, **refused** (not parked) |
  | `manual` *(default)* | everything else | whatever the tool says needs a human |
  | `accept_edits` | + the edits manual would park | `unrecoverable_when` calls |
  | `auto` | everything | nothing |

  Three things about it are load-bearing. **The tool catalogue is
  identical in all four** — filtering the array by mode reads as the
  tidier design and would throw away the whole ~21.6k-token cached prefix
  on every switch, since tools render ahead of system; planning refuses at
  call time instead, and the refusal goes back as a `tool_result` so the
  model re-plans rather than retrying. **A mode is a standing answer, not
  a bypass**: `accept_edits` and `auto` still mint a real
  `Tools::Confirmation` grant for a gated call, because `Base.call`
  re-checks the gate and must not learn to trust its caller — MCP has no
  modes and that boundary is the only door on that side. And **the mode
  travels with the turn**, stamped into the queued payload at enqueue, so
  switching mid-flight applies to the next turn rather than retroactively
  to the calls already running.
- **Every `tool_use` gets a `tool_result`.** The Messages API rejects a
  transcript with an unanswered call, so a parked turn stores the results
  already computed next to the calls still queued, and resuming replays
  them in order. A tool that raises still produces an error result rather
  than leaving the call dangling.
- **A spend ceiling per conversation ($10) and per day ($50)**, mirroring
  the ingestion one, off the exact `conversations.api_cost_micro_cents`.
  `Ingestion::UsageCost` carries explicit `claude-opus-5` rates for this —
  the fallback understates Opus by ~1.7x, and a ceiling that undercounts
  is worse than no ceiling. The daily figure sums
  `conversation_runs.cost_micro_cents` over the **runs that happened
  today**, not the lifetime spend of conversations created today: chats
  outlive a session, so charging a conversation's whole cost to its
  creation date left every continued conversation invisible to the wall.
- **Two walls, because rounds are not time.** `MAX_ITERATIONS` (20) bounds
  how many tool rounds a turn may take; `CHAT_TURN_DEADLINE_SECONDS`
  (default 600) bounds how long it may take to take them. Both were
  raised from 12 and 300 once real turns turned out to run eleven and
  twelve rounds — at that length the old figures were ending honest turns
  rather than catching stuck ones. Without the
  second, one round could sit for the full 240s upstream read timeout
  while `tick!` renewed the 120s lease at every step — a turn holding a
  conversation for the better part of an hour and looking healthy. The
  deadline is checked **between** rounds, the only point where every
  `tool_use` already has its `tool_result`, and ends the turn as a stored,
  replayable result (run state `failed`, outcome `timed_out`) rather than
  a raise.

Prompt caching: **two** breakpoints, and the second one is why the first
one's placement rule got stricter.

The first is on the last system block — tools render into the cached
prefix *before* system, so that one caches the whole tool catalog plus
the instructions plus the topology together. Nothing per-request may sit
above it.

The second rolls forward through `messages`: `AgentLoop#cacheable` marks
the last content block of the last message on every request, so the
conversation so far becomes a cached prefix for the next round. Without
it a turn's cost grew with the *square* of its length — a real
eleven-round turn billed 167,655 input tokens for a transcript only ever
a few thousand tokens long, because every round re-sent every earlier
round at full price.

The consequence for the first breakpoint is the part worth internalising.
A `messages` breakpoint's prefix is `tools → system → messages`, so the
volatile block *below* the system breakpoint is above the transcript and
counts for it. A per-request byte there no longer costs "just the
volatile block" — it costs the whole conversation's cache. That is why
`current_time` is bucketed to five minutes (`SystemPrompt::TIME_BUCKET`,
matching the ephemeral TTL) rather than second-resolution: at second
resolution the first round of every turn missed by construction, and a
single-round turn got strictly *worse*, writing the transcript at 1.25×
instead of reading it at 1.0×.

The profile snapshot and page context still sit below the system
breakpoint and are still per-turn — they are cached by the transcript
breakpoint within a turn, and change between turns whenever the profile
or the page does.

Both shapes the marker lands on are verified against the live API rather
than assumed — a trailing `text` block (round 1) and a trailing
`tool_result` block (every round after), each writing on the first call
and reading the whole prefix back on the second. The chat suite drives
`ScriptedClient` and has no cassettes by design, so that check is a
probe, not a test.

That system prefix — catalog, instructions, topology — plus the profile
snapshot below the breakpoint is built **once per turn**, not once per
round: it cannot change within a turn, and rebuilding it re-rendered 44
JSON schemas and walked the registry three more times to arrive at the
same bytes. `Tools::Registry.for` memoizes on the `Tools::Context`, which
is the object that fixes the answer — `user` is memoized on it and
`scopes` arrive at construction.

Messages store the Anthropic content-block array verbatim, including
`thinking` blocks — a thinking block's signature is rejected if it is
reconstructed rather than replayed.

### The HTTP surface

**Two transports over the same rows.** `GET /conversations/:id/stream` is
SSE for clients that can hold a connection open; `GET
/conversations/:id/events?after=N` returns the same narration as JSON for
clients that cannot. React Native's fetch is XHR-backed and exposes no
readable body, so the mobile app polls. Both read `conversation_events`
and share one cursor, so a client can switch between them without losing
its place.

**A turn runs in a job, not in the request.** `POST /messages` and
`/confirm` record the ask into `conversations.pending_turns` and enqueue
`Chat::CompletionJob`, answering `202` with the narration position to watch
from. `GET /conversations/:id/stream` tails `conversation_events` and
honours `Last-Event-ID`, so a reconnect resumes the narration instead of
waiting blind. `DELETE /conversations/:id/run` is the stop button — it
raises a flag the running turn reads at its next checkpoint, and it has to
be a separate request because the one that started the turn is busy.

| Route | What |
|---|---|
| `GET /api/v1/conversations` | The caller's own, newest first |
| `POST /api/v1/conversations` | Opens an empty one |
| `GET /api/v1/conversations/:id` | Replay: the transcript in client block shapes, plus any parked confirmation |
| `PATCH /api/v1/conversations/:id` | Sets `mode` — for switching without sending anything |
| `DELETE /api/v1/conversations/:id` | Removes it and its messages |
| `POST /api/v1/conversations/:id/messages` | Runs a turn, streaming SSE. Optional `mode` switches and sends in one request |
| `POST /api/v1/conversations/:id/confirm` | Answers a parked destructive call (`{"confirm": true\|false}`), streaming SSE |
| `POST /api/v1/attachments` | Multipart upload; returns a signed blob id for `start_menu_scan` |

A turn streams these events, each as one `data:` line of JSON:

`open` · `thinking_delta` · `text_delta` · `tool_use` · `tool_result` ·
then exactly one of `done`, `awaiting_confirmation`, or `error`.

Two properties follow from this being a chat and not an RPC:

- **The stream is a view, not the record.** Every turn is persisted as it
  runs, writes to a vanished client are swallowed, and the loop finishes
  server-side regardless. A dropped connection costs nothing — reopen the
  conversation and `show` replays it in the same block shapes. That is
  also what lets a 60-second turn survive a proxy timeout.
- **Validation happens before the stream opens.** Once headers are out
  there is no status code left to send, which is why the streaming turns
  live in their own controller: `ActionController::Live` rewrites the
  response object for *every* action in the controller it's included in.

Uploads exist so bytes never enter the agent's context — the chat handles
an id, and the vision call happens inside `start_menu_scan`, where text
injected into a photo has no tools to reach. The id is a **signed** id and
the blob records its uploader: blob primary keys are sequential integers,
so a raw id would let any account scan any other account's upload by
counting.

**Closed:** two turns fired concurrently on one conversation used to
interleave, and the UI was what prevented it. The server enforces it now
— `ConversationRun.acquire` is a lock held for the whole turn, and
`conversations.pending_turns` is the queue behind it, so a second ask
serializes rather than races. The composer no longer disables while a
turn runs; a message typed meanwhile is held client-side and sent when
the turn ends.

## Auth

Today `/mcp` accepts the same Devise JWT the REST API issues:

```
Authorization: Bearer <jwt>
```

No header means an anonymous caller, who still gets the public discovery
tools. A header that fails to authenticate is a **401**, not a silent
downgrade to anonymous — a client with a stale token needs to know to
refresh rather than quietly lose access to its own profile.

### Scoped tokens (least privilege)

A Devise JWT carries everything the account can do — for an admin, the
taxonomy, the moderation queue, and every user's role. That is a lot of
authority to hand something whose job is usually "read menus for me".

`McpToken` is the alternative: a credential that names what it may touch,
lists, and revokes on its own without ending other sessions.

Manage them at **/profile/settings → Connected apps**, or from a shell:

```bash
bin/rails "mcp:issue[you@example.com,Claude Code,discovery:read profile:read]"
bin/rails "mcp:list[you@example.com]"
bin/rails "mcp:revoke[<token id>]"
bin/rails mcp:scopes          # every grantable scope
```

The secret prints once; only its SHA-256 is stored, so a leaked database
is not a leaked set of working credentials.

Scopes are `<domain>:<read|write>`, **derived from `Registry::DOMAINS`**
rather than listed — a new domain cannot ship without a scope for it. The
read/write split follows each tool's own `read_only_hint`, so it cannot
drift from what the tool does. A write grant implies the read on the same
domain; the reverse never holds.

Enforcement lives in `Tools::Base` alongside the audience check, because
they are different questions and both must pass: audience asks *may this
person*, scope asks *may this credential*. An admin using a read-only
token is still an admin, and the token still may not write.

`Registry.for` filters on scope as well, so the catalogue a scoped
credential sees describes only what that credential can actually do.
Showing a read-only token the write tools would have a model pick one,
fail, and spend a turn learning what the list could have told it.
`Tools::Base` remains the boundary; the filter is what keeps the catalogue
honest.

`Topology.workflows_for` checks each workflow's steps against that same
filtered catalogue, and `WorkflowPrompts.for` delegates to it, so the map
and the offered prompts narrow with the tool list rather than deciding
separately. Audience alone is not enough here: a scoped credential can be
signed in, clear every audience check, and still lack the scope a step
needs.

**`meta` is ungated.** `describe_capabilities` is the server describing
itself, and what it describes is already filtered to the caller, so leaving
it reachable leaks nothing. Gating it would cost a great deal:
`discovery:read` is doorkeeper's `default_scopes`, so an OAuth client that
did not think to ask for `meta:read` would be told by the server
instructions to read a map it cannot reach.

The exemption is `Tools::Scopes::UNGATED_DOMAINS`, not a special case in
the registry, because **both** the catalogue and `Tools::Base#enforce_scope!`
ask that module. Exempting a domain in only one of them lists a tool that
then refuses to run — the exact wasted turn the exemption exists to
prevent. An ungated domain also drops out of `Scopes.available`, so no
consent screen asks permission for something nothing checks.

**An unscoped credential is unrestricted.** Every JWT issued before this
existed carries no scopes, and treating that as "denied" would lock out
every working integration.

### Connecting Claude Code

```bash
claude mcp add --transport http biteworthy https://<api-host>/mcp \
  --header "Authorization: Bearer $BITEWORTHY_JWT"
```

Get a token by logging in against the API:

```bash
curl -s -X POST https://<api-host>/api/v1/auth/login \
  -H 'content-type: application/json' \
  -d '{"user":{"email":"you@example.com","password":"…"}}' -i | grep -i '^authorization:'
```

### Public distribution — OAuth 2.1 (M8) — SHIPPED

A client in a connector directory has nobody to email for a credential, so
the whole flow has to work with no person at a terminal. It does:

| Endpoint | What it is |
|---|---|
| `POST /oauth/register` | RFC 7591 dynamic client registration. Unauthenticated by design; rate limited to 5/hour/IP. Public clients only — no secret is ever issued. |
| `GET /oauth/authorize` | Doorkeeper. Redirects to the consent screen in apps/web, then issues a code. PKCE `S256` required; `plain` refused. |
| `POST /oauth/token` | Code + `code_verifier` → access token (2h) + refresh token. Tokens stored as digests. |
| `GET /.well-known/oauth-protected-resource[/mcp]` | RFC 9728. Names the authorization server guarding `/mcp`. |
| `GET /.well-known/oauth-authorization-server[/mcp]` | RFC 8414. Endpoints, grant types, `S256`, and every grantable scope. |

A 401 from `/mcp` carries
`WWW-Authenticate: Bearer …, resource_metadata="…/.well-known/oauth-protected-resource/mcp"`,
which is the thread a cold client pulls to authorize itself.

**Scopes are the same vocabulary as `McpToken`** — derived from
`Registry::DOMAINS`, enforced in `Tools::Base`. An OAuth grant and a
personal token mean exactly the same thing to a tool, so there is no second
authorization model. `Tools::Scopes.describe` turns each into a sentence,
because `profile:write` is not something a person can agree to on the merits.

#### Consent lives in apps/web, not in Rails

This app is `api_only` and has no signed-in browser: the session cookie
only carries OmniAuth's `state`, and the JWT lives in an HttpOnly cookie
owned by the web origin that a browser never sends here. Rendering consent
in Rails would mean a second login surface — a second place to get rate
limiting, lockout, and password reset right.

So the flow hands off, and what carries approval across the origin boundary
is a **handoff token bound to a digest of the exact authorize parameters**
(`Oauth::Handoff`, 5-minute TTL). Same principle as the chat's confirmation
fingerprint: an approval is only valid for the request it was given for.
Change the scope, the client, or the redirect URI on the way back and the
digest stops matching, so the browser lands on consent again instead of
getting a grant.

```
client → GET /oauth/authorize
       → 302 apps/web /oauth/consent?return_to=…
       → person approves (web knows who is signed in)
       → POST /api/v1/oauth/consent  → handoff token
       → GET /oauth/authorize?…&handoff=…  → code
       → POST /oauth/token (+ code_verifier) → access token
```

The consent screen shows the client name, **the registered redirect URI**,
and a sentence per scope. The redirect URI is checked against what the
client registered (`URIChecker.valid_for_authorization?`) before it renders
— otherwise the screen would display one destination while doorkeeper
honoured another, and the "cancel" path would be an open redirect.

#### Disconnecting an app

`use_doorkeeper` skips `:authorized_applications` — the gem's own
management UI assumes a browser session this API does not have — so
`GET`/`DELETE /api/v1/connected_apps` is the replacement, surfaced at
`/profile/settings`. Revoking covers **tokens and grants** for that
application and that person: a client sitting on an unexchanged
authorization code must not be able to walk straight back in.

The list selects on `revoked_at IS NULL` and deliberately **not** on
expiry (`Doorkeeper::Application.authorized_for`). An access token lives
two hours; the grant behind it lives until revoked, because the client
refreshes. Filtering on "unexpired" would empty the list two hours after
every connection and tell people they had disconnected an app that was
still reading their profile.

**`connected_at` comes from the newest `AccessGrant`, not from the oldest
live token.** `previous_refresh_token` exists on the tokens table, so
`refresh_token_revoked_on_use?` is true and doorkeeper revokes the prior
row the first time a refreshed token is used — after a week of two-hourly
refreshes only the newest row is unrevoked, and the oldest-live-token
reading would render a week-old grant as "Connected today". A grant row is
written only by `/oauth/authorize` and never by a refresh, which makes it
the record of an actual approval. Newest rather than oldest because
disconnecting and reconnecting is a new connection.

**The row shows the registered redirect host, not only the name.**
Registration is unauthenticated, so a name is a claim: two clients can both
call themselves "Claude Desktop" and one of them can be hostile. Consent
answers that by showing the destination alongside the name, and a list you
revoke from has to be at least as decidable as the screen you approved on.

The refresh chain itself still has no absolute lifetime — a grant lasts
until someone ends it. That is now a decision rather than an oversight,
because there is a way to end it.

#### Two deliberate departures from the spec text

- **DCR rather than Client ID Metadata Documents.** CIMD is preferred in the
  current spec and DCR is marked legacy, but the clients that exist today
  register dynamically. DCR ships; CIMD can be added beside it without
  changing anything else.
- **`insufficient_scope` stays in the JSON-RPC result, not an HTTP 403.** A
  scope failure means one tool call was out of bounds; the *request*
  authenticated fine, and a JSON-RPC batch has no single HTTP status that
  could describe it. `Tools::Base` returns `isError` with the reason, which
  is what an MCP client can actually act on.

**RFC 8707 audience** is validated at consent (`resource` must name this
server's `/mcp`), not stored per token. The handoff digest covers every
authorize parameter, so a `resource` that passed cannot be swapped
afterwards. Storing it per token would need `custom_access_token_attributes`
and a column; worth doing if we ever guard a second resource.

**Anonymous discovery still works.** `/mcp` with no credential returns the
public discovery tools rather than a 401, which is a product feature — you
can browse menus without an account. The consequence is that a client which
never probes the well-known documents never learns OAuth exists. Clients
following the current MCP spec do probe; that is the bet.

## Transport notes

- **`/mcp` is rate limited per credential, not per IP.** The general
  rack-attack rule keys on `/api/`, and this door does not live there — so
  until 2026-08-09 it had no ceiling at all, with `get_menu` (every item at
  a restaurant, filtered in Ruby) reachable anonymously and unbounded.
  Credentialed callers get 120/minute keyed on a SHA-256 of the bearer, so
  every client behind one company's NAT does not share a bucket and
  throttle each other; anonymous callers get 30/minute keyed on IP, which
  is plenty for browsing and less headroom than something accountable
  gets. `/oauth/authorize` and `/oauth/token` are covered too — not as a
  brute-force guard (PKCE and hashed secrets handle that) but because each
  hit runs a lookup and `/oauth/token` writes a row.
- **A throttled MCP request is an HTTP 429, not a JSON-RPC error.** The
  rejection happens in middleware, before anything JSON-RPC exists to
  answer into. `Retry-After` is the part a client can act on.
- **Stateless mode is mandatory.** `StreamableHTTPTransport`'s stateful mode
  keeps sessions in process memory, which breaks the moment Puma runs a
  second worker or Kamal rolls a second container. Stateless makes every
  POST self-contained; we give up server-initiated notifications, which we
  don't use. In stateless mode responses are plain JSON — never SSE.
- **Host allow-listing.** The transport's DNS-rebinding guard allow-lists
  loopback and 403s everything else. Rails' own host authorization has
  already vetted `Host` by the time a request reaches the controller, so we
  pass the vetted host through rather than duplicating a list Rails owns.
  The guard's `Origin` check — the half that stops a browser cross-origin
  POST — stays in force; set `WEB_ORIGIN` when the browser app is on a
  different origin than the API.

## Testing

```bash
DATABASE_URL=postgres://localhost/biteworthy_test bundle exec rspec spec/services/tools spec/requests/mcp_spec.rb
```

Against a running server:

```bash
npx @modelcontextprotocol/inspector          # then point it at http://localhost:3000/mcp
```
