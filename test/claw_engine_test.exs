defmodule ClawEngineTest do
  use ExUnit.Case, async: true

  defmodule TestRepo do
  end

  test "child_specs can build a fully embedded engine" do
    assert [] =
             ClawEngine.child_specs(
               start_repo: false,
               start_http_server: false,
               start_engine_registry: false
             )
  end

  test "child_specs include the standalone children when enabled" do
    children =
      ClawEngine.child_specs(
        repo: TestRepo,
        start_repo: true,
        start_http_server: true,
        start_engine_registry: true
      )

    assert length(children) == 3
    assert ClawEngine.Engine.Registry in children
    assert TestRepo in children
    assert ClawEngineWeb.Endpoint.child_spec() in children
  end

  test "child_spec uses the configured supervisor name" do
    child_spec =
      ClawEngine.child_spec(
        supervisor_name: ClawEngine.EmbeddedSupervisor,
        start_http_server: false
      )

    assert child_spec.id == ClawEngine.EmbeddedSupervisor

    assert child_spec.start ==
             {ClawEngine, :start_link,
              [[supervisor_name: ClawEngine.EmbeddedSupervisor, start_http_server: false]]}
  end

  test "returns the bundled migration path" do
    assert ClawEngine.migrations_path()
           |> String.ends_with?("priv/repo/migrations")
  end

  test "returns the configured repo module" do
    original_repo = Application.get_env(:claw_engine, :repo)

    Application.put_env(:claw_engine, :repo, TestRepo)

    on_exit(fn ->
      Application.put_env(:claw_engine, :repo, original_repo)
    end)

    assert ClawEngine.repo() == TestRepo
  end
end
