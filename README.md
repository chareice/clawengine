# OpenClaw Zalify

Elixir bootstrap for Zalify's OpenClaw control plane.

The initial scope is intentionally small:

- expose a tiny HTTP service for local health and readiness checks
- keep OpenClaw running locally through Docker Compose
- verify that the Elixir service can reach the OpenClaw Gateway

The next step after this bootstrap is a real WebSocket RPC adapter for
`agents.*`, `agents.files.*`, and session routing.

## Stack

- Elixir `1.18.4`
- Erlang/OTP `27.3.4`
- Bandit + Plug for the HTTP surface
- Docker Compose for the local OpenClaw Gateway

## Local setup

```bash
mise install
mix deps.get
cp .env.example .env
docker compose up -d openclaw-gateway
mix openclaw.probe
mix test
mix run --no-halt
```

The HTTP server listens on `http://127.0.0.1:4000` by default.

## Environment

```bash
HTTP_PORT=4000
OPENCLAW_GATEWAY_URL=ws://127.0.0.1:18789
OPENCLAW_GATEWAY_TOKEN=change-me
OPENCLAW_PROBE_TIMEOUT_MS=1500
OPENCLAW_GATEWAY_BIND=lan
```

## Endpoints

- `GET /health` returns service health
- `GET /ready` returns OpenClaw readiness based on token presence and gateway reachability

## Docker Compose

The repository includes a local OpenClaw Gateway harness:

```bash
docker compose up -d openclaw-gateway
docker compose logs -f openclaw-gateway
docker compose down
```

The compose file uses the official image `ghcr.io/openclaw/openclaw:latest` and
binds the gateway to `127.0.0.1:18789`.
For local bootstrap, the tracked OpenClaw config disables the Control UI so the
container can run without extra browser-origin configuration.
