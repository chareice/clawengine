import Config

config :openclaw_zalify,
  agents_service: OpenClawZalify.Agents,
  agents_store: OpenClawZalify.Agents.PostgresStore,
  openclaw_admin_client: OpenClawZalify.OpenClaw.AdminClient,
  openclaw_probe: OpenClawZalify.OpenClaw.Probe,
  start_http_server: true,
  start_repo: true

config :openclaw_zalify, ecto_repos: [OpenClawZalify.Repo]

import_config "#{config_env()}.exs"
