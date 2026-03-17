import Config

load_env_file? =
  System.get_env("OPENCLAW_LOAD_ENV_FILE", "true")
  |> String.trim()
  |> String.downcase()
  |> then(&(&1 not in ["0", "false", "no"]))

config :claw_engine, load_env_file: load_env_file?

if config_env() != :test and load_env_file? do
  unless Code.ensure_loaded?(ClawEngine.EnvFile) do
    Code.require_file("../lib/claw_engine/env_file.ex", __DIR__)
  end

  ClawEngine.EnvFile.load_system(ClawEngine.EnvFile.default_path())
end

config :claw_engine,
  http_port: String.to_integer(System.get_env("HTTP_PORT", "4000"))

database_path =
  System.get_env("DATABASE_PATH") ||
    Path.expand("../.data/clawengine_dev.sqlite3", __DIR__)

File.mkdir_p!(Path.dirname(database_path))

config :claw_engine, ClawEngine.Repo,
  database: database_path,
  pool_size: String.to_integer(System.get_env("DATABASE_POOL_SIZE", "1")),
  busy_timeout: String.to_integer(System.get_env("DATABASE_BUSY_TIMEOUT_MS", "5000")),
  journal_mode: :wal,
  temp_store: :memory
