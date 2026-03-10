defmodule OpenClawZalify.Spaces do
  @moduledoc """
  Generic space orchestration for one self-hosted business instance.
  """

  alias OpenClawZalify.Agents
  alias OpenClawZalify.Agents.AgentRecord
  alias OpenClawZalify.Engine.Space

  @type provision_attrs :: %{
          optional(:display_name) => String.t(),
          optional(:role_prompt) => String.t(),
          optional(:identity_md) => String.t(),
          optional(:soul_md) => String.t(),
          optional(:user_md) => String.t(),
          optional(:model_ref) => String.t(),
          optional(:memory_enabled) => boolean()
        }

  @spec get_instance() :: {:ok, OpenClawZalify.Engine.Instance.t()}
  def get_instance do
    registry().get_instance()
  end

  @spec reload_engine_config() :: {:ok, OpenClawZalify.Engine.Snapshot.t()} | {:error, term()}
  def reload_engine_config do
    registry().reload()
  end

  @spec list_spaces() :: {:ok, [Space.t()]}
  def list_spaces do
    registry().list_spaces()
  end

  @spec get_space(String.t()) :: {:ok, Space.t() | nil} | {:error, term()}
  def get_space(space_id) when is_binary(space_id) do
    registry().get_space(String.trim(space_id))
  end

  @spec get_space_agent(String.t()) ::
          {:ok, %{space: Space.t(), agent: AgentRecord.t()} | nil} | {:error, term()}
  def get_space_agent(space_id) when is_binary(space_id) do
    with {:ok, %Space{} = space} <- fetch_space(space_id),
         {:ok, %AgentRecord{} = agent} <- agents_service().get_workspace_agent(space.id) do
      {:ok, %{space: space, agent: agent}}
    else
      {:ok, nil} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec provision_space_agent(String.t(), provision_attrs()) ::
          {:ok, %{created?: boolean(), space: Space.t(), agent: AgentRecord.t()}}
          | {:error, term()}
  def provision_space_agent(space_id, attrs \\ %{})
      when is_binary(space_id) and is_map(attrs) do
    with {:ok, %Space{} = space} <- fetch_space(space_id),
         {:ok, %{created?: created?, agent: %AgentRecord{} = agent}} <-
           agents_service().provision_workspace_agent(space.id, provision_attrs(space, attrs)) do
      {:ok, %{created?: created?, space: space, agent: agent}}
    end
  end

  @spec delete_space_agent(String.t()) ::
          {:ok, %{deleted?: boolean(), space: Space.t() | nil, agent: AgentRecord.t() | nil}}
          | {:error, term()}
  def delete_space_agent(space_id) when is_binary(space_id) do
    space_id = String.trim(space_id)

    space =
      case registry().get_space(space_id) do
        {:ok, %Space{} = loaded_space} -> loaded_space
        _other -> nil
      end

    with {:ok, %{deleted?: deleted?, agent: agent}} <-
           agents_service().delete_workspace_agent(space_id) do
      {:ok, %{deleted?: deleted?, space: space, agent: agent}}
    end
  end

  @spec list_space_agent_files(String.t()) ::
          {:ok, %{space: Space.t(), agent: AgentRecord.t(), files: [map()]}}
          | {:ok, nil}
          | {:error, term()}
  def list_space_agent_files(space_id) when is_binary(space_id) do
    with {:ok, %Space{} = space} <- fetch_space(space_id),
         {:ok, %{agent: %AgentRecord{} = agent, files: files}} <-
           agents_service().list_workspace_agent_files(space.id) do
      {:ok, %{space: space, agent: agent, files: files}}
    else
      {:ok, nil} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec get_space_agent_file(String.t(), String.t()) ::
          {:ok, %{space: Space.t(), agent: AgentRecord.t(), file: map()}}
          | {:ok, nil}
          | {:error, term()}
  def get_space_agent_file(space_id, name)
      when is_binary(space_id) and is_binary(name) do
    with {:ok, %Space{} = space} <- fetch_space(space_id),
         {:ok, %{agent: %AgentRecord{} = agent, file: file}} <-
           agents_service().get_workspace_agent_file(space.id, String.trim(name)) do
      {:ok, %{space: space, agent: agent, file: file}}
    else
      {:ok, nil} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_space(space_id) do
    case registry().get_space(String.trim(space_id)) do
      {:ok, %Space{} = space} -> {:ok, space}
      {:ok, nil} -> {:error, {:not_found, :space}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp provision_attrs(%Space{} = space, attrs) do
    %{
      agent_name: space.agent_name,
      workspace_path: space.workspace_path,
      display_name: normalize_text(attrs[:display_name]) || space.display_name,
      role_prompt: normalize_text(attrs[:role_prompt]) || space.role_prompt,
      identity_md: normalize_text(attrs[:identity_md]) || space.identity_md,
      soul_md: normalize_text(attrs[:soul_md]) || space.soul_md,
      user_md: normalize_text(attrs[:user_md]) || space.user_md,
      model_ref: normalize_text(attrs[:model_ref]) || space.model_ref,
      memory_enabled: Map.get(attrs, :memory_enabled, space.memory_enabled)
    }
  end

  defp normalize_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_text(_value), do: nil

  defp agents_service do
    Application.get_env(:openclaw_zalify, :agents_service, Agents)
  end

  defp registry do
    Application.get_env(:openclaw_zalify, :engine_registry, OpenClawZalify.Engine.Registry)
  end
end
