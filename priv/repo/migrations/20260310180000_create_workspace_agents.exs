defmodule OpenClawZalify.Repo.Migrations.CreateWorkspaceAgents do
  use Ecto.Migration

  def change do
    create table(:workspace_agent_mappings, primary_key: false) do
      add :workspace_id, :text, primary_key: true
      add :agent_id, :text, null: false
      add :status, :text, null: false
      add :runtime_mode, :text, null: false, default: "shared"
      add :workspace_path, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:workspace_agent_mappings, [:agent_id])

    create table(:agent_profiles, primary_key: false) do
      add :workspace_id,
          references(:workspace_agent_mappings,
            column: :workspace_id,
            type: :text,
            on_delete: :delete_all
          ),
          primary_key: true

      add :display_name, :text, null: false
      add :role_prompt, :text
      add :identity_md, :text
      add :soul_md, :text
      add :user_md, :text
      add :model_ref, :text
      add :memory_enabled, :boolean, null: false, default: true

      timestamps(type: :utc_datetime_usec)
    end
  end
end
