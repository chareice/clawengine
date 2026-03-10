defmodule OpenClawZalify.Chat do
  @moduledoc """
  Chat control-plane service for workspace-scoped OpenClaw sessions.
  """

  alias OpenClawZalify.Agents
  alias OpenClawZalify.Agents.AgentRecord
  alias OpenClawZalify.Chat.SessionRecord
  alias OpenClawZalify.Config

  @type send_opts :: [
          {:stream_ref, term()},
          {:stream_to, pid()},
          {:idempotency_key, String.t()},
          {:timeout_ms, pos_integer()}
        ]

  @spec send_message(String.t() | nil, String.t() | nil, String.t(), send_opts()) ::
          {:ok, %{session: SessionRecord.t(), agent: AgentRecord.t()}} | {:error, term()}
  def send_message(workspace_id, session_id, message, opts)
      when (is_binary(workspace_id) or is_nil(workspace_id)) and
             (is_binary(session_id) or is_nil(session_id)) and is_binary(message) and
             is_list(opts) do
    workspace_id = normalize_optional_text(workspace_id)
    session_id = normalize_optional_text(session_id)
    message = String.trim(message)

    with :ok <- validate_message(message),
         {:ok, {session, agent}} <- resolve_session_and_agent(workspace_id, session_id),
         :ok <- maybe_patch_session_model(session, agent),
         {:ok, _pid} <-
           chat_client().start_stream(
             stream_to: Keyword.fetch!(opts, :stream_to),
             stream_ref: Keyword.fetch!(opts, :stream_ref),
             session_id: session.id,
             session_key: session.openclaw_session_key,
             message: message,
             idempotency_key: Keyword.get(opts, :idempotency_key, Ecto.UUID.generate()),
             timeout_ms: Keyword.get(opts, :timeout_ms, Config.openclaw_chat_timeout_ms())
           ) do
      {:ok, %{session: session, agent: agent}}
    end
  end

  @spec get_history(String.t(), pos_integer()) ::
          {:ok, %{session: SessionRecord.t(), history: map()}} | {:error, term()}
  def get_history(session_id, limit \\ 50)
      when is_binary(session_id) and is_integer(limit) do
    session_id = String.trim(session_id)

    with :ok <- validate_session_id(session_id),
         :ok <- validate_limit(limit),
         {:ok, %SessionRecord{} = session} <- fetch_session(session_id),
         {:ok, history} <- chat_gateway().chat_history(session.openclaw_session_key, limit) do
      {:ok, %{session: session, history: history}}
    end
  end

  @spec abort_run(String.t(), String.t() | nil) ::
          {:ok, %{session: SessionRecord.t(), result: map()}} | {:error, term()}
  def abort_run(session_id, run_id \\ nil)
      when is_binary(session_id) and (is_binary(run_id) or is_nil(run_id)) do
    session_id = String.trim(session_id)
    run_id = normalize_optional_text(run_id)

    with :ok <- validate_session_id(session_id),
         {:ok, %SessionRecord{} = session} <- fetch_session(session_id),
         {:ok, result} <- chat_gateway().abort_chat(session.openclaw_session_key, run_id) do
      {:ok, %{session: session, result: result}}
    end
  end

  @spec serialize_session(SessionRecord.t()) :: map()
  def serialize_session(%SessionRecord{} = session) do
    %{
      id: session.id,
      workspace_id: session.workspace_id,
      agent_id: session.agent_id,
      status: session.status
    }
  end

  defp resolve_session_and_agent(workspace_id, nil) do
    with :ok <- validate_workspace_id(workspace_id),
         {:ok, %AgentRecord{} = agent} <- ensure_workspace_agent(workspace_id),
         {:ok, session} <- create_session(workspace_id, agent) do
      {:ok, {session, agent}}
    end
  end

  defp resolve_session_and_agent(workspace_id, session_id) do
    with {:ok, %SessionRecord{} = session} <- fetch_session(session_id),
         :ok <- maybe_validate_workspace_match(session, workspace_id),
         {:ok, %AgentRecord{} = agent} <- ensure_workspace_agent(session.workspace_id) do
      {:ok, {session, agent}}
    end
  end

  defp ensure_workspace_agent(workspace_id) do
    case agents_service().get_workspace_agent(workspace_id) do
      {:ok, %AgentRecord{} = agent} ->
        {:ok, agent}

      {:ok, nil} ->
        case agents_service().provision_workspace_agent(workspace_id, %{}) do
          {:ok, %{agent: %AgentRecord{} = agent}} -> {:ok, agent}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_session(workspace_id, %AgentRecord{} = agent) do
    session_id = Ecto.UUID.generate()

    session_store().create_session(%{
      id: session_id,
      workspace_id: workspace_id,
      agent_id: agent.agent_id,
      openclaw_session_key: openclaw_session_key(agent.agent_id, session_id),
      status: "active"
    })
  end

  defp fetch_session(session_id) do
    case session_store().get_session(session_id) do
      {:ok, %SessionRecord{} = session} -> {:ok, session}
      {:ok, nil} -> {:error, {:not_found, :session}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_patch_session_model(_session, %AgentRecord{model_ref: nil}), do: :ok
  defp maybe_patch_session_model(_session, %AgentRecord{model_ref: ""}), do: :ok

  defp maybe_patch_session_model(%SessionRecord{} = session, %AgentRecord{model_ref: model_ref}) do
    case chat_gateway().patch_session_model(session.openclaw_session_key, model_ref) do
      {:ok, _payload} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_validate_workspace_match(_session, nil), do: :ok

  defp maybe_validate_workspace_match(%SessionRecord{} = session, workspace_id) do
    if session.workspace_id == workspace_id do
      :ok
    else
      {:error, {:validation, %{workspace_id: ["does not match the existing session"]}}}
    end
  end

  defp openclaw_session_key(agent_id, session_id) do
    "agent:#{agent_id}:web:direct:#{String.downcase(session_id)}"
  end

  defp validate_workspace_id(nil),
    do: {:error, {:validation, %{workspace_id: ["is required when session_id is missing"]}}}

  defp validate_workspace_id(""),
    do: {:error, {:validation, %{workspace_id: ["can't be blank"]}}}

  defp validate_workspace_id(_workspace_id), do: :ok

  defp validate_session_id(""), do: {:error, {:validation, %{session_id: ["can't be blank"]}}}
  defp validate_session_id(_session_id), do: :ok

  defp validate_message(""), do: {:error, {:validation, %{message: ["can't be blank"]}}}
  defp validate_message(_message), do: :ok

  defp validate_limit(limit) when limit < 1 do
    {:error, {:validation, %{limit: ["must be greater than 0"]}}}
  end

  defp validate_limit(limit) when limit > 200 do
    {:error, {:validation, %{limit: ["must be less than or equal to 200"]}}}
  end

  defp validate_limit(_limit), do: :ok

  defp normalize_optional_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_text(_value), do: nil

  defp agents_service do
    Application.get_env(:openclaw_zalify, :agents_service, Agents)
  end

  defp session_store do
    Application.get_env(:openclaw_zalify, :chat_store, OpenClawZalify.Chat.PostgresStore)
  end

  defp chat_gateway do
    Application.get_env(
      :openclaw_zalify,
      :openclaw_chat_gateway,
      OpenClawZalify.OpenClaw.ChatGateway
    )
  end

  defp chat_client do
    Application.get_env(
      :openclaw_zalify,
      :openclaw_chat_client,
      OpenClawZalify.OpenClaw.ChatClient
    )
  end
end
