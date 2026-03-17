defmodule ClawEngine do
  @moduledoc """
  ClawEngine bootstrap for OpenClaw integration.

  The engine can run in two modes:

  - standalone: the OTP application starts its own supervisor tree
  - embedded: a host application starts the engine with `runtime: false`
    and includes `ClawEngine` in its own supervision tree
  """

  @default_supervisor_name ClawEngine.Supervisor

  @type start_option ::
          {:repo, module()}
          | {:start_repo, boolean()}
          | {:start_http_server, boolean()}
          | {:start_engine_registry, boolean()}
          | {:supervisor_name, atom()}

  @type start_options :: [start_option()]

  @doc """
  Returns the application version.
  """
  @spec version() :: String.t()
  def version do
    case Application.spec(:claw_engine, :vsn) do
      nil -> "0.0.0"
      version -> to_string(version)
    end
  end

  @doc """
  Returns the bundled migration path for the engine repo.
  """
  @spec migrations_path() :: String.t()
  def migrations_path do
    Application.app_dir(:claw_engine, "priv/repo/migrations")
  end

  @doc """
  Returns the configured repo module used for engine persistence.
  """
  @spec repo() :: module()
  def repo do
    Application.get_env(:claw_engine, :repo, ClawEngine.Repo)
  end

  @doc """
  Returns the child specs required to run the engine.

  The host application can use this to inspect or embed the engine without
  starting the standalone HTTP service.
  """
  @spec child_specs(start_options()) :: [Supervisor.child_spec()]
  def child_specs(opts \\ []) when is_list(opts) do
    config = startup_config(opts)

    []
    |> maybe_add_engine_registry(config)
    |> maybe_add_repo(config)
    |> maybe_add_http_server(config)
  end

  @doc """
  Starts the engine supervisor.

  This is the entry point used both by the standalone OTP application and by
  host applications embedding the engine as a dependency.
  """
  @spec start_link(start_options()) :: Supervisor.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    config = startup_config(opts)
    children = child_specs(opts)

    Supervisor.start_link(children, strategy: :one_for_one, name: config.supervisor_name)
  end

  @doc """
  Returns a supervisor child spec for embedding the engine in another app.
  """
  @spec child_spec(start_options()) :: Supervisor.child_spec()
  def child_spec(opts) when is_list(opts) do
    %{
      id: Keyword.get(opts, :supervisor_name, @default_supervisor_name),
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @doc false
  @spec startup_config(start_options()) :: %{
          repo: module(),
          start_repo: boolean(),
          start_http_server: boolean(),
          start_engine_registry: boolean(),
          supervisor_name: atom()
        }
  def startup_config(opts \\ []) when is_list(opts) do
    %{
      repo: Keyword.get(opts, :repo, repo()),
      start_repo: fetch_boolean_option(opts, :start_repo, true),
      start_http_server: fetch_boolean_option(opts, :start_http_server, true),
      start_engine_registry: fetch_boolean_option(opts, :start_engine_registry, true),
      supervisor_name: Keyword.get(opts, :supervisor_name, @default_supervisor_name)
    }
  end

  defp maybe_add_repo(children, %{start_repo: true, repo: repo}) do
    [repo | children]
  end

  defp maybe_add_repo(children, _config), do: children

  defp maybe_add_http_server(children, %{start_http_server: true}) do
    children ++ [ClawEngineWeb.Endpoint.child_spec()]
  end

  defp maybe_add_http_server(children, _config), do: children

  defp maybe_add_engine_registry(children, %{start_engine_registry: true}) do
    children ++ [ClawEngine.Engine.Registry]
  end

  defp maybe_add_engine_registry(children, _config), do: children

  defp fetch_boolean_option(opts, key, default) do
    Keyword.get(opts, key, Application.get_env(:claw_engine, key, default))
  end
end
