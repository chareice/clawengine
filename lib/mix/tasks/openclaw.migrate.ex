defmodule Mix.Tasks.Openclaw.Migrate do
  @shortdoc "Runs ClawEngine migrations on the configured repo"
  @moduledoc """
  Runs the bundled ClawEngine migrations on the configured repo.

  This task is intended for both standalone usage and embedded usage from a
  host application that depends on `openclaw_zalify`.
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("loadpaths")
    Mix.Task.run("compile")

    {:ok, _started} = Application.ensure_all_started(:ecto_sql)

    Ecto.Migrator.with_repo(OpenClawZalify.repo(), fn repo ->
      Ecto.Migrator.run(repo, OpenClawZalify.migrations_path(), :up, all: true)
    end)
  end
end
