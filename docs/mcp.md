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
| `app/services/tools/discovery/` | Public read tools |
| `app/services/tools/profile/` | Signed-in write tools |
| `app/controllers/mcp_controller.rb` | Transport adapter. No domain logic |

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
  recover from. Unexpected exceptions deliberately escape — a bug must not
  look like a recoverable domain error, or the model retries it forever.
- **Fence extracted text with `untrusted(...)`.** Dish names and
  descriptions came from strangers' photos and scraped pages.
- **Take slugs, not UUIDs**, on write tools. Models handle slugs reliably
  and `search_taxonomy` resolves them.

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
