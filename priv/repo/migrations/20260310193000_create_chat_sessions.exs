defmodule ClawEngine.Repo.Migrations.CreateChatSessions do
  use Ecto.Migration

  def change do
    create table(:chat_sessions, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :workspace_id,
          references(:workspace_agent_mappings,
            column: :workspace_id,
            type: :text,
            on_delete: :delete_all
          ),
          null: false

      add :agent_id, :text, null: false
      add :openclaw_session_key, :text, null: false
      add :status, :text, null: false, default: "active"

      timestamps(type: :utc_datetime_usec)
    end

    create index(:chat_sessions, [:workspace_id])
    create index(:chat_sessions, [:agent_id])
    create unique_index(:chat_sessions, [:openclaw_session_key])
  end
end
