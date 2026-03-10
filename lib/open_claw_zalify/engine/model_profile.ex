defmodule OpenClawZalify.Engine.ModelProfile do
  @moduledoc """
  Resolved model profile that a business instance can assign to spaces.
  """

  @enforce_keys [:id]
  defstruct [
    :id,
    :label,
    :model_ref,
    :reasoning_level,
    :timeout_ms,
    :raw
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          label: String.t() | nil,
          model_ref: String.t() | nil,
          reasoning_level: String.t() | nil,
          timeout_ms: pos_integer() | nil,
          raw: map() | nil
        }
end
