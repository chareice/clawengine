defmodule ClawEngine.Agents do
  @moduledoc """
  First control-plane slice for managing one OpenClaw agent per workspace.
  """

  alias ClawEngine.Agents.AgentRecord
  alias ClawEngine.Config

  @default_file_sync_retry_delays_ms [250, 500, 1_000]

  @type provision_attrs :: %{
          optional(:agent_name) => String.t(),
          optional(:workspace_path) => String.t(),
          optional(:display_name) => String.t(),
          optional(:role_prompt) => String.t(),
          optional(:identity_md) => String.t(),
          optional(:soul_md) => String.t(),
          optional(:user_md) => String.t(),
          optional(:model_ref) => String.t(),
          optional(:memory_enabled) => boolean()
        }

  @spec get_workspace_agent(String.t()) :: {:ok, AgentRecord.t() | nil} | {:error, term()}
  def get_workspace_agent(workspace_id) when is_binary(workspace_id) do
    store().get_workspace_agent(String.trim(workspace_id))
  end

  @spec delete_workspace_agent(String.t()) ::
          {:ok, %{deleted?: boolean(), agent: AgentRecord.t() | nil}} | {:error, term()}
  def delete_workspace_agent(workspace_id) when is_binary(workspace_id) do
    workspace_id = String.trim(workspace_id)

    with :ok <- validate_workspace_id(workspace_id),
         {:ok, existing} <- store().get_workspace_agent(workspace_id) do
      case existing do
        %AgentRecord{} = record ->
          with :ok <- delete_remote_agent(record.agent_id),
               {:ok, deleted_record} <- store().delete_workspace_agent(workspace_id) do
            {:ok, %{deleted?: true, agent: deleted_record || record}}
          end

        nil ->
          {:ok, %{deleted?: false, agent: nil}}
      end
    end
  end

  @spec list_workspace_agent_files(String.t()) ::
          {:ok, %{agent: AgentRecord.t(), files: [map()]}} | {:ok, nil} | {:error, term()}
  def list_workspace_agent_files(workspace_id) when is_binary(workspace_id) do
    workspace_id = String.trim(workspace_id)

    with :ok <- validate_workspace_id(workspace_id),
         {:ok, existing} <- store().get_workspace_agent(workspace_id) do
      case existing do
        %AgentRecord{} = record ->
          with {:ok, payload} <- admin_client().list_agent_files(record.agent_id) do
            {:ok, %{agent: record, files: Map.get(payload, "files", [])}}
          end

        nil ->
          {:ok, nil}
      end
    end
  end

  @spec get_workspace_agent_file(String.t(), String.t()) ::
          {:ok, %{agent: AgentRecord.t(), file: map()}} | {:ok, nil} | {:error, term()}
  def get_workspace_agent_file(workspace_id, name)
      when is_binary(workspace_id) and is_binary(name) do
    workspace_id = String.trim(workspace_id)
    name = String.trim(name)

    with :ok <- validate_workspace_id(workspace_id),
         :ok <- validate_file_name(name),
         {:ok, existing} <- store().get_workspace_agent(workspace_id) do
      case existing do
        %AgentRecord{} = record ->
          with {:ok, payload} <- admin_client().get_agent_file(record.agent_id, name) do
            {:ok, %{agent: record, file: Map.get(payload, "file", %{})}}
          end

        nil ->
          {:ok, nil}
      end
    end
  end

  @spec provision_workspace_agent(String.t(), provision_attrs()) ::
          {:ok, %{created?: boolean(), agent: AgentRecord.t()}} | {:error, term()}
  def provision_workspace_agent(workspace_id, attrs)
      when is_binary(workspace_id) and is_map(attrs) do
    workspace_id = String.trim(workspace_id)

    with :ok <- validate_workspace_id(workspace_id),
         {:ok, existing} <- store().get_workspace_agent(workspace_id) do
      case existing do
        %AgentRecord{} = record ->
          {:ok, %{created?: false, agent: record}}

        nil ->
          create_workspace_agent(workspace_id, attrs)
      end
    end
  end

  @spec agent_name_for_workspace(String.t()) :: String.t()
  def agent_name_for_workspace(workspace_id) do
    workspace_id
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_-]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> "workspace"
      normalized -> normalized
    end
    |> then(&"space-#{&1}")
  end

  defp create_workspace_agent(workspace_id, attrs) do
    agent_name = present_text(attrs[:agent_name]) || agent_name_for_workspace(workspace_id)

    workspace_path =
      present_text(attrs[:workspace_path]) ||
        Path.join(Config.openclaw_workspace_root(), agent_name)

    with {:ok, created_agent} <-
           admin_client().create_agent(%{
             name: agent_name,
             workspace: workspace_path
           }),
         :ok <- sync_workspace_files(created_agent.agent_id, workspace_id, attrs),
         {:ok, record} <-
           store().upsert_workspace_agent(%{
             workspace_id: workspace_id,
             agent_id: created_agent.agent_id,
             status: "active",
             runtime_mode: "shared",
             workspace_path: created_agent.workspace,
             display_name: display_name(workspace_id, attrs),
             role_prompt: present_text(attrs[:role_prompt]),
             identity_md: identity_md(workspace_id, attrs),
             soul_md: soul_md(workspace_id, attrs),
             user_md: user_md(workspace_id, attrs),
             model_ref: present_text(attrs[:model_ref]),
             memory_enabled: Map.get(attrs, :memory_enabled, true)
           }) do
      {:ok, %{created?: true, agent: record}}
    end
  end

  defp sync_workspace_files(agent_id, workspace_id, attrs) do
    files = [
      {"IDENTITY.md", identity_md(workspace_id, attrs)},
      {"SOUL.md", soul_md(workspace_id, attrs)},
      {"USER.md", user_md(workspace_id, attrs)}
    ]

    Enum.reduce_while(files, :ok, fn {name, content}, :ok ->
      case set_agent_file_with_retry(agent_id, name, content, file_sync_retry_delays_ms()) do
        {:ok, _result} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp set_agent_file_with_retry(agent_id, name, content, retry_delays_ms) do
    case admin_client().set_agent_file(agent_id, name, content) do
      {:ok, _result} = ok ->
        ok

      {:error, reason} = error ->
        case retry_delays_ms do
          [delay_ms | rest] ->
            if retryable_file_sync_error?(reason) do
              if delay_ms > 0, do: Process.sleep(delay_ms)
              set_agent_file_with_retry(agent_id, name, content, rest)
            else
              error
            end

          _other ->
            error
        end
    end
  end

  defp validate_workspace_id(""), do: {:error, {:validation, %{workspace_id: ["can't be blank"]}}}
  defp validate_workspace_id(_workspace_id), do: :ok

  defp validate_file_name(""), do: {:error, {:validation, %{name: ["can't be blank"]}}}
  defp validate_file_name(_name), do: :ok

  defp display_name(workspace_id, attrs) do
    present_text(attrs[:display_name]) || "Space Agent #{workspace_id}"
  end

  defp identity_md(workspace_id, attrs) do
    present_text(attrs[:identity_md]) ||
      """
      # Identity

      - Space ID: #{workspace_id}
      - Display Name: #{display_name(workspace_id, attrs)}
      - Runtime: OpenClaw Engine
      """
  end

  defp soul_md(workspace_id, attrs) do
    present_text(attrs[:soul_md]) ||
      """
      # Soul

      You are the assistant for space #{workspace_id}.
      Prefer precise, operational answers and use business tools when data is required.
      """
  end

  defp user_md(workspace_id, attrs) do
    present_text(attrs[:user_md]) ||
      """
      # User

      The current space is #{workspace_id}.
      Keep responses concise, helpful, and action-oriented.
      """
  end

  defp present_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present_text(_value), do: nil

  defp delete_remote_agent(agent_id) do
    case admin_client().delete_agent(agent_id) do
      {:ok, _payload} ->
        :ok

      {:error, {:request_failed, %{"code" => "INVALID_REQUEST", "message" => message}}}
      when is_binary(message) ->
        if String.contains?(String.downcase(message), "not found") do
          :ok
        else
          {:error, {:request_failed, %{"code" => "INVALID_REQUEST", "message" => message}}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp retryable_file_sync_error?(
         {:request_failed, %{"code" => "INVALID_REQUEST", "message" => message}}
       )
       when is_binary(message) do
    String.contains?(String.downcase(message), "unknown agent id")
  end

  defp retryable_file_sync_error?(_reason), do: false

  defp file_sync_retry_delays_ms do
    Application.get_env(
      :claw_engine,
      :agents_file_sync_retry_delays_ms,
      @default_file_sync_retry_delays_ms
    )
  end

  defp store do
    Application.get_env(:claw_engine, :agents_store, ClawEngine.Agents.RepoStore)
  end

  defp admin_client do
    Application.get_env(
      :claw_engine,
      :openclaw_admin_client,
      ClawEngine.OpenClaw.AdminClient
    )
  end
end
