defmodule OpenClawZalify.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:openclaw_zalify, :start_http_server, true) do
        [OpenClawZalifyWeb.Endpoint.child_spec()]
      else
        []
      end

    opts = [strategy: :one_for_one, name: OpenClawZalify.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
