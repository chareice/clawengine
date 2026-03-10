defmodule OpenClawZalify.Engine.Snapshot do
  @moduledoc """
  In-memory snapshot of the loaded engine configuration.
  """

  alias OpenClawZalify.Engine.Instance
  alias OpenClawZalify.Engine.ModelProfile
  alias OpenClawZalify.Engine.Space

  @enforce_keys [:config_root, :instance, :spaces, :model_profiles, :loaded_at]
  defstruct [
    :config_root,
    :instance,
    :spaces,
    :model_profiles,
    :loaded_at
  ]

  @type t :: %__MODULE__{
          config_root: String.t(),
          instance: Instance.t(),
          spaces: %{optional(String.t()) => Space.t()},
          model_profiles: %{optional(String.t()) => ModelProfile.t()},
          loaded_at: DateTime.t()
        }
end
