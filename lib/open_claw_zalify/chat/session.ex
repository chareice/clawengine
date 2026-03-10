defmodule OpenClawZalify.Chat.Session do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  @foreign_key_type :string

  schema "chat_sessions" do
    field(:workspace_id, :string)
    field(:agent_id, :string)
    field(:openclaw_session_key, :string)
    field(:status, :string, default: "active")

    belongs_to(:mapping, OpenClawZalify.Agents.WorkspaceAgentMapping,
      define_field: false,
      foreign_key: :workspace_id,
      references: :workspace_id,
      type: :string
    )

    timestamps(type: :utc_datetime_usec)
  end

  @fields [:id, :workspace_id, :agent_id, :openclaw_session_key, :status]

  def changeset(session, attrs) do
    session
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> validate_inclusion(:status, ["active", "archived"])
    |> unique_constraint(:id)
    |> unique_constraint(:openclaw_session_key)
  end
end
