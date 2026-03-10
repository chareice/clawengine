defmodule OpenClawZalify.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      []
      |> maybe_add_engine_registry()
      |> maybe_add_repo()
      |> maybe_add_http_server()

    opts = [strategy: :one_for_one, name: OpenClawZalify.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_add_repo(children) do
    if Application.get_env(:openclaw_zalify, :start_repo, true) do
      [OpenClawZalify.Repo | children]
    else
      children
    end
  end

  defp maybe_add_http_server(children) do
    if Application.get_env(:openclaw_zalify, :start_http_server, true) do
      children ++ [OpenClawZalifyWeb.Endpoint.child_spec()]
    else
      children
    end
  end

  defp maybe_add_engine_registry(children) do
    if Application.get_env(:openclaw_zalify, :start_engine_registry, true) do
      children ++ [OpenClawZalify.Engine.Registry]
    else
      children
    end
  end
end
