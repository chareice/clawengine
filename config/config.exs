import Config

config :openclaw_zalify,
  engine_registry: OpenClawZalify.Engine.Registry,
  spaces_service: OpenClawZalify.Spaces,
  agents_service: OpenClawZalify.Agents,
  agents_store: OpenClawZalify.Agents.RepoStore,
  openclaw_admin_client: OpenClawZalify.OpenClaw.AdminClient,
  openclaw_probe: OpenClawZalify.OpenClaw.Probe,
  repo: OpenClawZalify.Repo,
  load_env_file: true,
  start_engine_registry: true,
  start_http_server: true,
  start_repo: true

config :openclaw_zalify, ecto_repos: [OpenClawZalify.Repo]

import_config "#{config_env()}.exs"
