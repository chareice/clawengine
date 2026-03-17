defmodule ClawEngine.Engine.Registry do
  @moduledoc """
  Process-local registry for the loaded engine configuration snapshot.
  """

  use GenServer

  alias ClawEngine.Config
  alias ClawEngine.Engine.Loader
  alias ClawEngine.Engine.Snapshot

  @type state :: Snapshot.t()

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec snapshot() :: Snapshot.t()
  def snapshot do
    GenServer.call(__MODULE__, :snapshot)
  end

  @spec get_instance() :: {:ok, ClawEngine.Engine.Instance.t()}
  def get_instance do
    {:ok, snapshot().instance}
  end

  @spec list_spaces() :: {:ok, [ClawEngine.Engine.Space.t()]}
  def list_spaces do
    {:ok, snapshot().spaces |> Map.values() |> Enum.sort_by(& &1.id)}
  end

  @spec get_space(String.t()) :: {:ok, ClawEngine.Engine.Space.t() | nil}
  def get_space(space_id) when is_binary(space_id) do
    normalized = String.trim(space_id)
    {:ok, Map.get(snapshot().spaces, normalized)}
  end

  @spec get_model_profile(String.t() | nil) ::
          {:ok, ClawEngine.Engine.ModelProfile.t() | nil}
  def get_model_profile(nil), do: {:ok, nil}

  def get_model_profile(profile_id) when is_binary(profile_id) do
    normalized = String.trim(profile_id)
    {:ok, Map.get(snapshot().model_profiles, normalized)}
  end

  @spec reload() :: {:ok, Snapshot.t()} | {:error, term()}
  def reload do
    GenServer.call(__MODULE__, :reload, 15_000)
  end

  @impl true
  def init(_opts) do
    case Loader.load(Config.engine_config_root()) do
      {:ok, snapshot} -> {:ok, snapshot}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:reload, _from, state) do
    case Loader.load(Config.engine_config_root()) do
      {:ok, snapshot} -> {:reply, {:ok, snapshot}, snapshot}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end
end
