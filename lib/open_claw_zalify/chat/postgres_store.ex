defmodule OpenClawZalify.Chat.PostgresStore do
  @moduledoc """
  PostgreSQL-backed chat session persistence.
  """

  @behaviour OpenClawZalify.Chat.Store

  alias OpenClawZalify.Chat.Session
  alias OpenClawZalify.Chat.SessionRecord
  alias OpenClawZalify.Repo

  @impl true
  def get_session(session_id) do
    {:ok, Repo.get(Session, session_id) |> to_record()}
  rescue
    err -> {:error, err}
  end

  @impl true
  def create_session(attrs) do
    %Session{}
    |> Session.changeset(%{
      id: attrs.id,
      workspace_id: attrs.workspace_id,
      agent_id: attrs.agent_id,
      openclaw_session_key: attrs.openclaw_session_key,
      status: attrs.status
    })
    |> Repo.insert()
    |> case do
      {:ok, session} -> {:ok, to_record(session)}
      {:error, reason} -> {:error, reason}
    end
  rescue
    err -> {:error, err}
  end

  defp to_record(nil), do: nil

  defp to_record(%Session{} = session) do
    %SessionRecord{
      id: session.id,
      workspace_id: session.workspace_id,
      agent_id: session.agent_id,
      openclaw_session_key: session.openclaw_session_key,
      status: session.status,
      inserted_at: session.inserted_at,
      updated_at: session.updated_at
    }
  end
end
