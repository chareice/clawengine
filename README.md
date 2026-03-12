# ClawEngine

Self-hosted Elixir control plane for one business-owned OpenClaw instance.

This engine is designed for the deployment model discussed in the architecture
notes:

- one business runs one engine instance
- the instance serves many internal tenants as `spaces`
- each space can resolve to one OpenClaw agent
- model profiles, prompts, and defaults come from a config directory
- sessions, runs, and agent bindings stay in SQLite by default

A business like Zalify can run this engine, but the runtime is now driven by a
generic `instance -> spaces -> agents -> sessions` model instead of hard-coded
workspace rules.

## Current scope

- load a business instance from `ENGINE_CONFIG_ROOT`
- expose instance and space APIs over HTTP
- provision one OpenClaw agent per configured space
- proxy `agents.files.*` through the control plane
- expose chat over `GET /ws/chat`
- persist agent bindings and chat sessions in SQLite
- support business-configured model profiles for each space

## Stack

- Elixir `1.18.4`
- Erlang/OTP `27.3.4`
- Bandit + Plug for the HTTP surface
- Ecto + SQLite for runtime state
- `yaml_elixir` for config-directory loading
- Docker Compose for the local OpenClaw Gateway

## Local setup

```bash
mise install
mix deps.get
cp .env.example .env
docker compose up -d openclaw-gateway
mix openclaw.migrate
mix openclaw.probe
mix test
mix run --no-halt
```

The HTTP server listens on `http://127.0.0.1:4000` by default.

If you do not set `ENGINE_CONFIG_ROOT`, the service loads the sample business
config bundled in [`priv/engine/default`](priv/engine/default).

## Environment

```bash
HTTP_PORT=4000
ENGINE_CONFIG_ROOT=/abs/path/to/your/business-engine-config

OPENCLAW_GATEWAY_URL=ws://127.0.0.1:18789
OPENCLAW_GATEWAY_TOKEN=change-me
OPENCLAW_PROBE_TIMEOUT_MS=1500
OPENCLAW_ADMIN_TIMEOUT_MS=5000
OPENCLAW_CHAT_TIMEOUT_MS=60000
OPENCLAW_WORKSPACE_ROOT=/home/node/.openclaw/workspace/spaces

OPENCLAW_GATEWAY_BIND=lan
OPENCLAW_GATEWAY_PORT=18789
OPENCLAW_GATEWAY_INTERNAL_PORT=18789

DATABASE_PATH=.data/clawengine_dev.sqlite3
DATABASE_POOL_SIZE=1
DATABASE_BUSY_TIMEOUT_MS=5000
```

`ENGINE_CONFIG_ROOT` is the main product interface for a self-hosted business.
The engine reads that directory on startup and can reload it through
`POST /api/instance/reload`.

## Embedded mode

ClawEngine can also run inside a host Elixir application instead of being
deployed as a separate HTTP service.

Recommended dependency setup in the host app:

```elixir
{:openclaw_zalify, path: "/abs/path/to/openclaw-zalify", runtime: false}
```

Recommended host config:

```elixir
config :openclaw_zalify,
  repo: HostApp.Repo,
  load_env_file: false,
  start_http_server: false,
  start_repo: false,
  start_engine_registry: true
```

Recommended host supervision tree:

```elixir
children = [
  {OpenClawZalify,
   repo: HostApp.Repo,
   start_http_server: false,
   start_repo: false,
   start_engine_registry: true}
]
```

In embedded mode, the host app should:

- manage the engine config via `config :openclaw_zalify, ...`
- run `mix openclaw.migrate` against the configured repo
- call the engine services directly through `OpenClawZalify.Spaces`,
  `OpenClawZalify.Agents`, and `OpenClawZalify.Chat`

This keeps one BEAM process while still reusing the full ClawEngine control
plane internally.

## Config directory

The engine expects a directory shaped like this:

```text
engine/
  instance.yaml
  models/
    default.yaml
    premium.yaml
  spaces/
    shop-123.yaml
    shop-456.yaml
  templates/
    merchant-support/
      IDENTITY.md
      SOUL.md
      USER.md
```

The bundled sample config lives under
[`priv/engine/default`](priv/engine/default).

### `instance.yaml`

```yaml
id: acme
name: ACME Commerce

agent:
  name_template: "{{instance.id}}-{{space.slug}}"
  workspace_path_template: "{{openclaw.workspace_root}}/{{instance.id}}/{{space.slug}}"

defaults:
  template_set: merchant-support
  model_profile: default
  tool_profile: default
  memory_enabled: true
```

### `models/default.yaml`

```yaml
id: default
label: Default
model_ref: deepseek/deepseek-chat
reasoning_level: off
timeout_ms: 45000
```

The current engine applies these model settings per session through
`sessions.patch` before `chat.send`.

### `spaces/shop-123.yaml`

```yaml
id: shop-123
name: Shop 123

agent:
  display_name: Shop 123 Assistant
  model_profile: default
  template_set: merchant-support
  memory_enabled: true

variables:
  region: sg
  storefront: shop-123.example.com
```

### `templates/merchant-support/IDENTITY.md`

```md
# Identity

- Business: {{instance.name}}
- Space ID: {{space.id}}
- Space Name: {{space.name}}
- Display Name: {{space.display_name}}
- Storefront: {{vars.storefront}}
```

The template renderer resolves `{{instance.*}}`, `{{space.*}}`, `{{model.*}}`,
`{{vars.*}}`, and `{{openclaw.workspace_root}}`.

## HTTP API

### Instance APIs

- `GET /api/instance`
- `POST /api/instance/reload`

`GET /api/instance` returns the loaded business instance metadata and current
space count.

### Space APIs

- `GET /api/spaces`
- `GET /api/spaces/:space_id`
- `GET /api/spaces/:space_id/agent`
- `POST /api/spaces/:space_id/agent/provision`
- `GET /api/spaces/:space_id/agent/files`
- `GET /api/spaces/:space_id/agent/files/:name`
- `DELETE /api/spaces/:space_id/agent`

Compatibility aliases are still available:

- `GET /api/workspaces/:workspace_id/ai-agent`
- `POST /api/workspaces/:workspace_id/ai-agent/provision`
- `GET /api/workspaces/:workspace_id/ai-agent/files`
- `GET /api/workspaces/:workspace_id/ai-agent/files/:name`
- `DELETE /api/workspaces/:workspace_id/ai-agent`

Example provision call:

```bash
curl -s -X POST http://127.0.0.1:4000/api/spaces/demo-shop/agent/provision \
  -H 'content-type: application/json' \
  -d '{"display_name":"Demo Shop Assistant"}'
```

## WebSocket chat

`GET /ws/chat` is the message plane. Clients connect to the Elixir layer, which
then bridges to OpenClaw over WebSocket.

Supported client frames:

- `ping`
- `send_message`
- `get_history`
- `abort_run`

Supported server frames:

- `pong`
- `session_ready`
- `run_started`
- `chat_event`
- `history`
- `run_aborted`
- `error`

### `send_message`

Request:

```json
{
  "type": "send_message",
  "request_id": "req-1",
  "space_id": "shop-123",
  "message": "Please reply with a confirmation token."
}
```

Response sequence:

```json
{
  "type": "session_ready",
  "request_id": "req-1",
  "session": {
    "id": "8f0cc0d5-58df-479a-b4c2-49e9b3724383",
    "space_id": "shop-123",
    "agent_id": "acme-shop-123",
    "status": "active"
  }
}
```

```json
{
  "type": "run_started",
  "request_id": "req-1",
  "session_id": "8f0cc0d5-58df-479a-b4c2-49e9b3724383",
  "session_key": "agent:acme-shop-123:web:direct:8f0cc0d5-58df-479a-b4c2-49e9b3724383",
  "run_id": "9db6e3f7-e9fb-4313-b54b-0df34ea3d36a",
  "status": "started"
}
```

```json
{
  "type": "chat_event",
  "request_id": "req-1",
  "session_id": "8f0cc0d5-58df-479a-b4c2-49e9b3724383",
  "run_id": "9db6e3f7-e9fb-4313-b54b-0df34ea3d36a",
  "state": "final",
  "message": {
    "role": "assistant",
    "content": [
      {
        "type": "text",
        "text": "WS_CHAT_E2E_OK"
      }
    ]
  }
}
```

Notes:

- when `session_id` is omitted, the engine creates a new chat session and
  derives an OpenClaw session key under the mapped space agent
- when `session_id` is present, `space_id` becomes optional
- `workspace_id` is accepted as a legacy alias for `space_id`
- `chat_event.state` can be `delta`, `final`, `error`, or `aborted`
- `OPENCLAW_CHAT_TIMEOUT_MS` is used when a space or caller does not override it

### `get_history`

```json
{
  "type": "get_history",
  "request_id": "req-history",
  "session_id": "8f0cc0d5-58df-479a-b4c2-49e9b3724383",
  "limit": 50
}
```

### `abort_run`

```json
{
  "type": "abort_run",
  "request_id": "req-abort",
  "session_id": "8f0cc0d5-58df-479a-b4c2-49e9b3724383",
  "run_id": "9db6e3f7-e9fb-4313-b54b-0df34ea3d36a"
}
```

## Runtime state

The config directory is the desired state.
The runtime state still lives in SQLite and OpenClaw workspace volumes:

- configured spaces and model profiles come from disk
- provisioned agent bindings are stored in SQLite
- chat sessions are stored in SQLite
- OpenClaw transcripts and workspace files live under `OPENCLAW_WORKSPACE_ROOT`

That split is intentional:

- config directory for static business rules
- database for mutable runtime state
- environment variables for secrets
