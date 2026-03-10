defmodule OpenClawZalify.Agents.WorkspaceAgentMapping do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:workspace_id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "workspace_agent_mappings" do
    field(:agent_id, :string)
    field(:status, :string)
    field(:runtime_mode, :string)
    field(:workspace_path, :string)

    has_one(:profile, OpenClawZalify.Agents.AgentProfile,
      foreign_key: :workspace_id,
      references: :workspace_id
    )

    timestamps(type: :utc_datetime_usec)
  end

  @fields [:workspace_id, :agent_id, :status, :runtime_mode, :workspace_path]

  def changeset(mapping, attrs) do
    mapping
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> validate_inclusion(:status, ["creating", "active", "failed", "deleting"])
    |> validate_inclusion(:runtime_mode, ["shared", "dedicated"])
    |> unique_constraint(:workspace_id)
    |> unique_constraint(:agent_id)
  end
end
