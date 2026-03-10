defmodule OpenClawZalifyWeb.Endpoint do
  @moduledoc false

  alias OpenClawZalify.Config

  @spec child_spec() :: Supervisor.child_spec()
  def child_spec do
    {Bandit, plug: OpenClawZalifyWeb.Router, scheme: :http, port: Config.http_port()}
  end
end
