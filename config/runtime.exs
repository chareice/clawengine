import Config

if config_env() != :test do
  unless Code.ensure_loaded?(OpenClawZalify.EnvFile) do
    Code.require_file("../lib/open_claw_zalify/env_file.ex", __DIR__)
  end

  OpenClawZalify.EnvFile.load_system(OpenClawZalify.EnvFile.default_path())
end

config :openclaw_zalify,
  http_port: String.to_integer(System.get_env("HTTP_PORT", "4000"))

database_url =
  System.get_env("DATABASE_URL") ||
    "ecto://postgres:postgres@127.0.0.1:5433/openclaw_zalify_dev"

config :openclaw_zalify, OpenClawZalify.Repo,
  url: database_url,
  pool_size: String.to_integer(System.get_env("DATABASE_POOL_SIZE", "10"))
