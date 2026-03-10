import Config

config :openclaw_zalify,
  http_port: String.to_integer(System.get_env("HTTP_PORT", "4000"))
