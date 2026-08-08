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
| `app/services/tools/registry.rb` | The catalog; `Registry.for(context)` filters by audience |
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
- **`audience` gates visibility, not just access.** `Registry.for(context)`
  drops tools the caller may not use, so a non-admin's `tools/list` never
  mentions them. `Tools::Base` re-checks at call time as defence in depth.
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
- **New tools are deferred by default in the chat.** Only the core domains
  (discovery, profile, meta) stay resident; everything else loads on demand
  via tool search, which is what keeps a cold turn from carrying 13k tokens
  of schema. Add a domain to `Chat::ToolCatalog::CORE_DOMAINS` only if it
  genuinely opens conversations.
- **Don't block a tool call on a slow LLM call.** Extraction runs in a job
  and `start_menu_scan` returns a scan id for the caller to poll. A tool
  that blocks for a minute times out real clients.

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
suggest_correction   (anyone signed in; queues, changes nothing)
                  →  list_suggestions   (owner or admin only)
                  →  resolve_suggestion (accept APPLIES it to the live dish)
```

The gate is `claimed_by_user_id` on the restaurant, set by
`claim_restaurant` → emailed token → `verify_claim`. Admins pass it too.

Accepting `remove_ingredient` deletes a join row, which un-hides that dish
for everyone avoiding the ingredient — the most dangerous write available
to a non-admin, which is why it carries `destructive_hint: true` and the
server instructions tell the model to say what accepting would change.

## The admin surface

Everything under `audience :admin` descends from `Tools::AdminBase`, which
is the only place that audience is declared. `Registry.for(context)` drops
them wholesale for non-admins, so a normal caller's `tools/list` never
mentions them.

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

`edit_place` and `edit_item` share their validation with the REST
controllers rather than reimplementing it: `Places::Writer` and
`Admin::ItemEditor` respectively. That is deliberate — both validate
before coercing, because Rails' casts are lossy in exactly the directions
that corrupt live data (`"monday".to_i` is `0`, `"25:99"` becomes "closed",
a non-numeric latitude becomes Null Island).

## The first-party chat

`Chat::AgentLoop` is the second front door: the same registry, the same
audience filter, the same server instructions, driven against
`claude-opus-5` with adaptive thinking. `Chat::ToolCatalog` renders the
MCP tool classes as Messages API tool definitions — one registry, two
wire formats, never two implementations.

Three things it enforces that a bare tool loop would not:

- **Confirmation before a destructive call.** The loop stops at the first
  tool whose `destructive_hint` is true and parks it in
  `conversations.pending_tool_call`. Nothing that publishes, deletes, or
  changes what a person is shown runs because a model decided to. Each
  such call needs its own answer, so a queue of them parks one at a time —
  confirming one does not pre-authorize the next.
- **Every `tool_use` gets a `tool_result`.** The Messages API rejects a
  transcript with an unanswered call, so a parked turn stores the results
  already computed next to the calls still queued, and resuming replays
  them in order. A tool that raises still produces an error result rather
  than leaving the call dangling.
- **A spend ceiling per conversation and per day**, mirroring the
  ingestion one, off `conversations.api_cost_cents`. `Ingestion::UsageCost`
  carries explicit `claude-opus-5` rates for this — the fallback
  understates Opus by ~1.7x, and a ceiling that undercounts is worse than
  no ceiling.

Prompt caching: tools render into the cached prefix **before** system, so
the single `cache_control` breakpoint goes on the last system block. That
caches the whole tool catalog plus the instructions plus the topology
together. Nothing per-request may sit above it.

Messages store the Anthropic content-block array verbatim, including
`thinking` blocks — a thinking block's signature is rejected if it is
reconstructed rather than replayed.

### The HTTP surface

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
| `DELETE /api/v1/conversations/:id` | Removes it and its messages |
| `POST /api/v1/conversations/:id/messages` | Runs a turn, streaming SSE |
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

**Known gap:** two turns fired concurrently on one conversation would
interleave. The UI disables the composer while streaming; the server does
not enforce it.

## Auth

Today `/mcp` accepts the same Devise JWT the REST API issues:

```
Authorization: Bearer <jwt>
```

No header means an anonymous caller, who still gets the public discovery
tools. A header that fails to authenticate is a **401**, not a silent
downgrade to anonymous — a client with a stale token needs to know to
refresh rather than quietly lose access to its own profile.

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

### What public distribution still needs (Phase 6)

Listing in the claude.ai connector directory means becoming an OAuth 2.1
resource server. Per the MCP authorization spec, the server **MUST**:

- serve `/.well-known/oauth-protected-resource` (RFC 9728) and point at an
  authorization server;
- answer 401 with `WWW-Authenticate: Bearer resource_metadata="…"`, and 403
  with `error="insufficient_scope"` plus the scopes needed;
- validate that each access token was issued **for this resource**
  (RFC 8707 audience binding).

The authorization server itself needs OAuth 2.1 with PKCE and either RFC
8414 metadata or OIDC Discovery. Client registration should support Client
ID Metadata Documents; Dynamic Client Registration (RFC 7591) is deprecated
in the current spec and only needed for backwards compatibility.

## Transport notes

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
