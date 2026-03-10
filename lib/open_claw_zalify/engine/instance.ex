defmodule OpenClawZalify.Engine.Instance do
  @moduledoc """
  Static instance-level configuration loaded from the engine config directory.
  """

  @enforce_keys [:id, :name, :agent_name_template, :workspace_path_template]
  defstruct [
    :id,
    :name,
    :agent_name_template,
    :workspace_path_template,
    :default_template_set,
    :default_model_profile_id,
    :default_tool_profile_id,
    :default_memory_enabled,
    :config_root
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          agent_name_template: String.t(),
          workspace_path_template: String.t(),
          default_template_set: String.t() | nil,
          default_model_profile_id: String.t() | nil,
          default_tool_profile_id: String.t() | nil,
          default_memory_enabled: boolean(),
          config_root: String.t() | nil
        }
end
