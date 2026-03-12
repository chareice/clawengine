defmodule OpenClawZalifyTest do
  use ExUnit.Case, async: true

  defmodule TestRepo do
  end

  test "child_specs can build a fully embedded engine" do
    assert [] =
             OpenClawZalify.child_specs(
               start_repo: false,
               start_http_server: false,
               start_engine_registry: false
             )
  end

  test "child_specs include the standalone children when enabled" do
    children =
      OpenClawZalify.child_specs(
        repo: TestRepo,
        start_repo: true,
        start_http_server: true,
        start_engine_registry: true
      )

    assert length(children) == 3
    assert OpenClawZalify.Engine.Registry in children
    assert TestRepo in children
    assert OpenClawZalifyWeb.Endpoint.child_spec() in children
  end

  test "child_spec uses the configured supervisor name" do
    child_spec =
      OpenClawZalify.child_spec(
        supervisor_name: OpenClawZalify.EmbeddedSupervisor,
        start_http_server: false
      )

    assert child_spec.id == OpenClawZalify.EmbeddedSupervisor

    assert child_spec.start ==
             {OpenClawZalify, :start_link,
              [[supervisor_name: OpenClawZalify.EmbeddedSupervisor, start_http_server: false]]}
  end

  test "returns the bundled migration path" do
    assert OpenClawZalify.migrations_path()
           |> String.ends_with?("priv/repo/migrations")
  end

  test "returns the configured repo module" do
    original_repo = Application.get_env(:openclaw_zalify, :repo)

    Application.put_env(:openclaw_zalify, :repo, TestRepo)

    on_exit(fn ->
      Application.put_env(:openclaw_zalify, :repo, original_repo)
    end)

    assert OpenClawZalify.repo() == TestRepo
  end
end
