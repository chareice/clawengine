defmodule OpenClawZalify.Agents.RepoStore do
  @moduledoc """
  Repo-backed workspace-agent persistence.
  """

  @behaviour OpenClawZalify.Agents.Store

  alias OpenClawZalify.Agents.AgentProfile
  alias OpenClawZalify.Agents.AgentRecord
  alias OpenClawZalify.Agents.WorkspaceAgentMapping
  import Ecto.Query

  @impl true
  def get_workspace_agent(workspace_id) do
    query =
      from(mapping in WorkspaceAgentMapping,
        where: mapping.workspace_id == ^workspace_id,
        left_join: profile in assoc(mapping, :profile),
        preload: [profile: profile]
      )

    {:ok, repo().one(query) |> to_record()}
  rescue
    err -> {:error, err}
  end

  @impl true
  def upsert_workspace_agent(attrs) do
    repo().transaction(fn ->
      mapping =
        repo().get(WorkspaceAgentMapping, attrs.workspace_id) ||
          %WorkspaceAgentMapping{workspace_id: attrs.workspace_id}

      mapping =
        mapping
        |> WorkspaceAgentMapping.changeset(%{
          workspace_id: attrs.workspace_id,
          agent_id: attrs.agent_id,
          status: attrs.status,
          runtime_mode: attrs.runtime_mode,
          workspace_path: attrs.workspace_path
        })
        |> repo().insert_or_update!()

      profile =
        repo().get(AgentProfile, attrs.workspace_id) ||
          %AgentProfile{workspace_id: attrs.workspace_id}

      profile =
        profile
        |> AgentProfile.changeset(%{
          workspace_id: attrs.workspace_id,
          display_name: attrs.display_name,
          role_prompt: attrs.role_prompt,
          identity_md: attrs.identity_md,
          soul_md: attrs.soul_md,
          user_md: attrs.user_md,
          model_ref: attrs.model_ref,
          memory_enabled: attrs.memory_enabled
        })
        |> repo().insert_or_update!()

      mapping
      |> Map.put(:profile, profile)
      |> to_record()
    end)
    |> case do
      {:ok, record} -> {:ok, record}
      {:error, reason} -> {:error, reason}
    end
  rescue
    err -> {:error, err}
  end

  @impl true
  def delete_workspace_agent(workspace_id) do
    repo().transaction(fn ->
      case repo().get(WorkspaceAgentMapping, workspace_id) do
        nil ->
          nil

        mapping ->
          mapping = repo().preload(mapping, :profile)
          record = to_record(mapping)
          repo().delete!(mapping)
          record
      end
    end)
    |> case do
      {:ok, record} -> {:ok, record}
      {:error, reason} -> {:error, reason}
    end
  rescue
    err -> {:error, err}
  end

  defp to_record(nil), do: nil

  defp to_record(%WorkspaceAgentMapping{} = mapping) do
    profile = Map.get(mapping, :profile)

    %AgentRecord{
      workspace_id: mapping.workspace_id,
      agent_id: mapping.agent_id,
      status: mapping.status,
      runtime_mode: mapping.runtime_mode,
      workspace_path: mapping.workspace_path,
      display_name: profile && profile.display_name,
      role_prompt: profile && profile.role_prompt,
      identity_md: profile && profile.identity_md,
      soul_md: profile && profile.soul_md,
      user_md: profile && profile.user_md,
      model_ref: profile && profile.model_ref,
      memory_enabled: profile && profile.memory_enabled,
      inserted_at: mapping.inserted_at,
      updated_at: mapping.updated_at
    }
  end

  defp repo do
    OpenClawZalify.repo()
  end
end
