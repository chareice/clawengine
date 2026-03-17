defmodule ClawEngine.Repo do
  use Ecto.Repo,
    otp_app: :claw_engine,
    adapter: Ecto.Adapters.SQLite3
end
