defmodule ClawEngine.OpenClaw.AdminClientTest do
  use ExUnit.Case, async: false

  alias ClawEngine.OpenClaw.AdminClient

  defmodule FakeClient do
    def request(opts, method, params) do
      send(self(), {:openclaw_request, opts, method, params})
      {:ok, %{"agentId" => params["agentId"], "ok" => true}}
    end
  end

  setup do
    original_client = Application.get_env(:claw_engine, :openclaw_client)
    original_load_env = Application.get_env(:claw_engine, :load_env_file, true)
    original_token = System.get_env("OPENCLAW_GATEWAY_TOKEN")

    Application.put_env(:claw_engine, :openclaw_client, FakeClient)
    Application.put_env(:claw_engine, :load_env_file, false)
    System.put_env("OPENCLAW_GATEWAY_TOKEN", "test-token")

    on_exit(fn ->
      Application.put_env(:claw_engine, :openclaw_client, original_client)
      Application.put_env(:claw_engine, :load_env_file, original_load_env)

      if is_binary(original_token) do
        System.put_env("OPENCLAW_GATEWAY_TOKEN", original_token)
      else
        System.delete_env("OPENCLAW_GATEWAY_TOKEN")
      end
    end)

    :ok
  end

  test "update_agent normalizes model_ref before calling Gateway" do
    assert {:ok, %{"agentId" => "admin-agent", "ok" => true}} =
             AdminClient.update_agent("admin-agent", %{model_ref: "openai:glm-5-turbo"})

    assert_received {:openclaw_request, opts, "agents.update",
                     %{"agentId" => "admin-agent", "model" => "openai/glm-5-turbo"}}

    assert opts[:token] == "test-token"
  end
end
