defmodule OpenClawZalify.Chat do
  @moduledoc """
  Chat control-plane service for space-scoped OpenClaw sessions.
  """

  alias OpenClawZalify.Agents.AgentRecord
  alias OpenClawZalify.Chat.SessionRecord
  alias OpenClawZalify.Config
  alias OpenClawZalify.Engine.Space
  alias OpenClawZalify.Spaces

  @type send_opts :: [
          {:stream_ref, term()},
          {:stream_to, pid()},
          {:idempotency_key, String.t()},
          {:timeout_ms, pos_integer()}
        ]

  @spec send_message(String.t() | nil, String.t() | nil, String.t(), send_opts()) ::
          {:ok, %{session: SessionRecord.t(), agent: AgentRecord.t(), space: Space.t()}}
          | {:error, term()}
  def send_message(space_id, session_id, message, opts)
      when (is_binary(space_id) or is_nil(space_id)) and
             (is_binary(session_id) or is_nil(session_id)) and is_binary(message) and
             is_list(opts) do
    space_id = normalize_optional_text(space_id)
    session_id = normalize_optional_text(session_id)
    message = String.trim(message)

    with :ok <- validate_message(message),
         {:ok, {session, agent, space}} <- resolve_session_and_agent(space_id, session_id),
         :ok <- maybe_patch_session_runtime(session, agent, space),
         {:ok, _pid} <-
           chat_client().start_stream(
             stream_to: Keyword.fetch!(opts, :stream_to),
             stream_ref: Keyword.fetch!(opts, :stream_ref),
             session_id: session.id,
             session_key: session.openclaw_session_key,
             message: message,
             idempotency_key: Keyword.get(opts, :idempotency_key, Ecto.UUID.generate()),
             timeout_ms:
               Keyword.get(
                 opts,
                 :timeout_ms,
                 space.timeout_ms || Config.openclaw_chat_timeout_ms()
               )
           ) do
      {:ok, %{session: session, agent: agent, space: space}}
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
      space_id: session.workspace_id,
      agent_id: session.agent_id,
      status: session.status
    }
  end

  defp resolve_session_and_agent(space_id, nil) do
    with :ok <- validate_space_id(space_id),
         {:ok, {%Space{} = space, %AgentRecord{} = agent}} <- ensure_space_agent(space_id),
         {:ok, session} <- create_session(space.id, agent) do
      {:ok, {session, agent, space}}
    end
  end

  defp resolve_session_and_agent(space_id, session_id) do
    with {:ok, %SessionRecord{} = session} <- fetch_session(session_id),
         :ok <- maybe_validate_space_match(session, space_id),
         {:ok, {%Space{} = space, %AgentRecord{} = agent}} <-
           ensure_space_agent(session.workspace_id) do
      {:ok, {session, agent, space}}
    end
  end

  defp ensure_space_agent(space_id) do
    case spaces_service().get_space_agent(space_id) do
      {:ok, %{space: %Space{} = space, agent: %AgentRecord{} = agent}} ->
        {:ok, {space, agent}}

      {:ok, nil} ->
        case spaces_service().provision_space_agent(space_id, %{}) do
          {:ok, %{space: %Space{} = space, agent: %AgentRecord{} = agent}} ->
            {:ok, {space, agent}}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_session(space_id, %AgentRecord{} = agent) do
    session_id = Ecto.UUID.generate()

    session_store().create_session(%{
      id: session_id,
      workspace_id: space_id,
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

  defp maybe_patch_session_runtime(
         %SessionRecord{} = session,
         %AgentRecord{} = agent,
         %Space{} = space
       ) do
    patch =
      %{
        model_ref: normalize_optional_text(agent.model_ref),
        reasoning_level: normalize_optional_text(space.reasoning_level)
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    case map_size(patch) do
      0 ->
        :ok

      _size ->
        case chat_gateway().patch_session(session.openclaw_session_key, patch) do
          {:ok, _payload} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp maybe_validate_space_match(_session, nil), do: :ok

  defp maybe_validate_space_match(%SessionRecord{} = session, space_id) do
    if session.workspace_id == space_id do
      :ok
    else
      {:error, {:validation, %{space_id: ["does not match the existing session"]}}}
    end
  end

  defp openclaw_session_key(agent_id, session_id) do
    "agent:#{agent_id}:web:direct:#{String.downcase(session_id)}"
  end

  defp validate_space_id(nil),
    do: {:error, {:validation, %{space_id: ["is required when session_id is missing"]}}}

  defp validate_space_id(""), do: {:error, {:validation, %{space_id: ["can't be blank"]}}}

  defp validate_space_id(_space_id), do: :ok

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

  defp spaces_service do
    Application.get_env(:openclaw_zalify, :spaces_service, Spaces)
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
