defmodule ClawEngine.Agents.AgentRecord do
  @moduledoc """
  Flattened workspace-agent record returned by the store layer.
  """

  @enforce_keys [:workspace_id, :agent_id, :status, :runtime_mode, :workspace_path]
  defstruct [
    :workspace_id,
    :agent_id,
    :status,
    :runtime_mode,
    :workspace_path,
    :display_name,
    :role_prompt,
    :identity_md,
    :soul_md,
    :user_md,
    :model_ref,
    :memory_enabled,
    :inserted_at,
    :updated_at
  ]

  @type t :: %__MODULE__{
          workspace_id: String.t(),
          agent_id: String.t(),
          status: String.t(),
          runtime_mode: String.t(),
          workspace_path: String.t(),
          display_name: String.t() | nil,
          role_prompt: String.t() | nil,
          identity_md: String.t() | nil,
          soul_md: String.t() | nil,
          user_md: String.t() | nil,
          model_ref: String.t() | nil,
          memory_enabled: boolean() | nil,
          inserted_at: NaiveDateTime.t() | DateTime.t() | nil,
          updated_at: NaiveDateTime.t() | DateTime.t() | nil
        }
end
