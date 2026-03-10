import Config

if config_env() != :test do
  unless Code.ensure_loaded?(OpenClawZalify.EnvFile) do
    Code.require_file("../lib/open_claw_zalify/env_file.ex", __DIR__)
  end

  OpenClawZalify.EnvFile.load_system(OpenClawZalify.EnvFile.default_path())
end

config :openclaw_zalify,
  http_port: String.to_integer(System.get_env("HTTP_PORT", "4000"))

database_path =
  System.get_env("DATABASE_PATH") ||
    Path.expand("../.data/clawengine_dev.sqlite3", __DIR__)

File.mkdir_p!(Path.dirname(database_path))

config :openclaw_zalify, OpenClawZalify.Repo,
  database: database_path,
  pool_size: String.to_integer(System.get_env("DATABASE_POOL_SIZE", "1")),
  busy_timeout: String.to_integer(System.get_env("DATABASE_BUSY_TIMEOUT_MS", "5000")),
  journal_mode: :wal,
  temp_store: :memory
