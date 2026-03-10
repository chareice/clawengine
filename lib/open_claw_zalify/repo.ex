defmodule OpenClawZalify.Repo do
  use Ecto.Repo,
    otp_app: :openclaw_zalify,
    adapter: Ecto.Adapters.Postgres
end
