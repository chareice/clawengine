# OpenClaw Zalify

Elixir bootstrap for Zalify's OpenClaw control plane.

The initial scope is intentionally small:

- expose a tiny HTTP service for local health and readiness checks
- keep OpenClaw running locally through Docker Compose
- verify that the Elixir service can reach the OpenClaw Gateway
- provision and query one OpenClaw agent per Zalify workspace

The current slice includes:

- a minimal OpenClaw admin RPC adapter over WebSocket
- `POST /api/workspaces/:workspace_id/ai-agent/provision`
- `GET /api/workspaces/:workspace_id/ai-agent`
- `GET /api/workspaces/:workspace_id/ai-agent/files`
- `GET /api/workspaces/:workspace_id/ai-agent/files/:name`
- `DELETE /api/workspaces/:workspace_id/ai-agent`
- `GET /ws/chat` for workspace-scoped chat sessions over WebSocket
- PostgreSQL persistence for workspace-to-agent mappings and agent profiles
- PostgreSQL persistence for `chat_sessions`

## Stack

- Elixir `1.18.4`
- Erlang/OTP `27.3.4`
- Bandit + Plug for the HTTP surface
- Ecto + PostgreSQL for persistence
- Docker Compose for the local OpenClaw Gateway

## Local setup

```bash
mise install
mix deps.get
cp .env.example .env
docker compose up -d postgres openclaw-gateway
mix ecto.create
mix ecto.migrate
mix openclaw.probe
mix test
mix run --no-halt
```

The HTTP server listens on `http://127.0.0.1:4000` by default.
If `127.0.0.1:18789` is already occupied on your machine, set a different
`OPENCLAW_GATEWAY_PORT` in `.env` and update `OPENCLAW_GATEWAY_URL` to match.

## Environment

```bash
HTTP_PORT=4000
OPENCLAW_GATEWAY_URL=ws://127.0.0.1:18789
OPENCLAW_GATEWAY_TOKEN=change-me
OPENCLAW_PROBE_TIMEOUT_MS=1500
OPENCLAW_ADMIN_TIMEOUT_MS=5000
OPENCLAW_CHAT_TIMEOUT_MS=60000
OPENCLAW_WORKSPACE_ROOT=/home/node/.openclaw/workspace/zalify
OPENCLAW_GATEWAY_BIND=lan
OPENCLAW_GATEWAY_INTERNAL_PORT=18789
POSTGRES_PORT=5433
DATABASE_URL=ecto://postgres:postgres@127.0.0.1:5433/openclaw_zalify_dev
```

`OPENCLAW_GATEWAY_PORT` is the host port exposed by Docker Compose.
`OPENCLAW_GATEWAY_INTERNAL_PORT` stays at `18789` unless you have a specific
reason to change the container's listening port as well.

## Endpoints

- `GET /health` returns service health
- `GET /ready` returns OpenClaw readiness based on token presence and gateway reachability
- `POST /api/workspaces/:workspace_id/ai-agent/provision` creates or reuses a workspace agent
- `GET /api/workspaces/:workspace_id/ai-agent` returns the stored workspace-agent mapping
- `GET /api/workspaces/:workspace_id/ai-agent/files` lists supported workspace files from OpenClaw
- `GET /api/workspaces/:workspace_id/ai-agent/files/:name` reads one supported workspace file
- `DELETE /api/workspaces/:workspace_id/ai-agent` deletes the OpenClaw agent and local mapping
- `GET /ws/chat` upgrades to a WebSocket session for chat control

## Docker Compose

The repository includes a local PostgreSQL database and OpenClaw Gateway harness:

```bash
docker compose up -d postgres openclaw-gateway
docker compose logs -f postgres
docker compose logs -f openclaw-gateway
docker compose down
```

The compose file uses the official image `ghcr.io/openclaw/openclaw:latest` and
binds the gateway to `127.0.0.1:18789`.
For local bootstrap, the tracked OpenClaw config disables the Control UI so the
container can run without extra browser-origin configuration. On first startup,
Docker Compose copies that tracked config template into the writable `.docker`
state directory so `agents.create` can update it normally.

## Provision flow

`POST /api/workspaces/:workspace_id/ai-agent/provision` does the following:

1. checks whether the workspace already has a mapping in PostgreSQL
2. creates an OpenClaw agent through `agents.create` when missing
3. writes `IDENTITY.md`, `SOUL.md`, and `USER.md` through `agents.files.set`
4. persists the workspace mapping and agent profile locally

`GET /api/workspaces/:workspace_id/ai-agent/files` and
`GET /api/workspaces/:workspace_id/ai-agent/files/:name` proxy OpenClaw's
`agents.files.list` and `agents.files.get` for the mapped agent.

`DELETE /api/workspaces/:workspace_id/ai-agent` deletes the mapped OpenClaw
agent through `agents.delete` and removes the local PostgreSQL mapping.

## WebSocket chat

`GET /ws/chat` is the chat message plane. Clients connect to Zalify's Elixir
layer, not directly to OpenClaw.

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
  "workspace_id": "shop-1",
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
    "workspace_id": "shop-1",
    "agent_id": "zalify-shop-1",
    "status": "active"
  }
}
```

```json
{
  "type": "run_started",
  "request_id": "req-1",
  "session_id": "8f0cc0d5-58df-479a-b4c2-49e9b3724383",
  "session_key": "agent:zalify-shop-1:web:direct:8f0cc0d5-58df-479a-b4c2-49e9b3724383",
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

- When `session_id` is omitted, Zalify creates a new `chat_sessions` record and
  derives an OpenClaw session key under the mapped agent.
- When `session_id` is present, `workspace_id` becomes optional and the existing
  chat session is reused.
- `chat_event.state` can be `delta`, `final`, `error`, or `aborted`.
- `OPENCLAW_CHAT_TIMEOUT_MS` controls how long Zalify will wait for OpenClaw to
  produce stream events before failing the run.

### `get_history`

Request:

```json
{
  "type": "get_history",
  "request_id": "req-history",
  "session_id": "8f0cc0d5-58df-479a-b4c2-49e9b3724383",
  "limit": 50
}
```

Response:

```json
{
  "type": "history",
  "request_id": "req-history",
  "session": {
    "id": "8f0cc0d5-58df-479a-b4c2-49e9b3724383",
    "workspace_id": "shop-1",
    "agent_id": "zalify-shop-1",
    "status": "active"
  },
  "messages": [
    {
      "role": "assistant"
    }
  ]
}
```

### `abort_run`

Request:

```json
{
  "type": "abort_run",
  "request_id": "req-abort",
  "session_id": "8f0cc0d5-58df-479a-b4c2-49e9b3724383",
  "run_id": "9db6e3f7-e9fb-4313-b54b-0df34ea3d36a"
}
```

Response:

```json
{
  "type": "run_aborted",
  "request_id": "req-abort",
  "session": {
    "id": "8f0cc0d5-58df-479a-b4c2-49e9b3724383",
    "workspace_id": "shop-1",
    "agent_id": "zalify-shop-1",
    "status": "active"
  },
  "aborted": true,
  "run_ids": [
    "9db6e3f7-e9fb-4313-b54b-0df34ea3d36a"
  ]
}
```

Validation and OpenClaw bridge failures are returned as:

```json
{
  "type": "error",
  "request_id": "req-1",
  "error": "validation_error",
  "details": {
    "type": [
      "is not supported"
    ]
  }
}
```
