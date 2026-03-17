defmodule ClawEngine.Agents.AgentProfile do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:workspace_id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "agent_profiles" do
    field(:display_name, :string)
    field(:role_prompt, :string)
    field(:identity_md, :string)
    field(:soul_md, :string)
    field(:user_md, :string)
    field(:model_ref, :string)
    field(:memory_enabled, :boolean, default: true)

    belongs_to(:mapping, ClawEngine.Agents.WorkspaceAgentMapping,
      define_field: false,
      foreign_key: :workspace_id,
      references: :workspace_id,
      type: :string
    )

    timestamps(type: :utc_datetime_usec)
  end

  @fields [
    :workspace_id,
    :display_name,
    :role_prompt,
    :identity_md,
    :soul_md,
    :user_md,
    :model_ref,
    :memory_enabled
  ]

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, @fields)
    |> validate_required([:workspace_id, :display_name, :memory_enabled])
    |> unique_constraint(:workspace_id)
  end
end
