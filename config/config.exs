import Config

config :claw_engine,
  engine_registry: ClawEngine.Engine.Registry,
  spaces_service: ClawEngine.Spaces,
  agents_service: ClawEngine.Agents,
  agents_store: ClawEngine.Agents.RepoStore,
  skills_runner: ClawEngine.Skills.ClawHubRunner,
  openclaw_admin_client: ClawEngine.OpenClaw.AdminClient,
  openclaw_probe: ClawEngine.OpenClaw.Probe,
  repo: ClawEngine.Repo,
  load_env_file: true,
  start_engine_registry: true,
  start_http_server: true,
  start_repo: true

config :claw_engine, ecto_repos: [ClawEngine.Repo]

import_config "#{config_env()}.exs"
