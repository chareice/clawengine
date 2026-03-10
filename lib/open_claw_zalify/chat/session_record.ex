defmodule OpenClawZalify.Chat.SessionRecord do
  @moduledoc """
  Flattened chat session record used by the service layer.
  """

  @enforce_keys [:id, :workspace_id, :agent_id, :openclaw_session_key, :status]
  defstruct [
    :id,
    :workspace_id,
    :agent_id,
    :openclaw_session_key,
    :status,
    :inserted_at,
    :updated_at
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          workspace_id: String.t(),
          agent_id: String.t(),
          openclaw_session_key: String.t(),
          status: String.t(),
          inserted_at: NaiveDateTime.t() | DateTime.t() | nil,
          updated_at: NaiveDateTime.t() | DateTime.t() | nil
        }
end
