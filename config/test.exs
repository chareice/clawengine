import Config

config :openclaw_zalify,
  agents_service: OpenClawZalify.Agents,
  agents_store: OpenClawZalify.Agents.RepoStore,
  openclaw_admin_client: OpenClawZalify.OpenClaw.AdminClient,
  start_http_server: false

config :openclaw_zalify,
  start_repo: false
