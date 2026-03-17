defmodule ClawEngineWeb.Endpoint do
  @moduledoc false

  alias ClawEngine.Config

  @spec child_spec() :: Supervisor.child_spec()
  def child_spec do
    {Bandit, plug: ClawEngineWeb.Router, scheme: :http, port: Config.http_port()}
  end
end
