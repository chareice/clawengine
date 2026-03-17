import Config

config :claw_engine,
  agents_service: ClawEngine.Agents,
  agents_store: ClawEngine.Agents.RepoStore,
  openclaw_admin_client: ClawEngine.OpenClaw.AdminClient,
  start_http_server: false

config :claw_engine,
  start_repo: false
