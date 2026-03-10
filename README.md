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
- PostgreSQL persistence for workspace-to-agent mappings and agent profiles

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
