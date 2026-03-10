defmodule OpenClawZalify.Engine.Space do
  @moduledoc """
  Resolved per-space configuration inside one business instance.
  """

  @enforce_keys [:id, :name, :slug, :agent_name, :workspace_path]
  defstruct [
    :id,
    :name,
    :slug,
    :display_name,
    :agent_name,
    :workspace_path,
    :template_set,
    :model_profile_id,
    :tool_profile_id,
    :model_ref,
    :reasoning_level,
    :timeout_ms,
    :role_prompt,
    :memory_enabled,
    :identity_md,
    :soul_md,
    :user_md,
    :variables,
    :raw
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          slug: String.t(),
          display_name: String.t() | nil,
          agent_name: String.t(),
          workspace_path: String.t(),
          template_set: String.t() | nil,
          model_profile_id: String.t() | nil,
          tool_profile_id: String.t() | nil,
          model_ref: String.t() | nil,
          reasoning_level: String.t() | nil,
          timeout_ms: pos_integer() | nil,
          role_prompt: String.t() | nil,
          memory_enabled: boolean(),
          identity_md: String.t(),
          soul_md: String.t(),
          user_md: String.t(),
          variables: map(),
          raw: map() | nil
        }
end
