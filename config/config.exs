import Config

config :openclaw_zalify,
  start_http_server: true,
  openclaw_probe: OpenClawZalify.OpenClaw.Probe

import_config "#{config_env()}.exs"
