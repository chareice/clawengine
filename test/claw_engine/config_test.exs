defmodule ClawEngine.ConfigTest do
  use ExUnit.Case, async: false

  alias ClawEngine.Config

  setup do
    original = %{
      "ENGINE_CONFIG_ROOT" => System.get_env("ENGINE_CONFIG_ROOT"),
      "HOME" => System.get_env("HOME"),
      "OPENCLAW_GATEWAY_URL" => System.get_env("OPENCLAW_GATEWAY_URL"),
      "OPENCLAW_GATEWAY_TOKEN" => System.get_env("OPENCLAW_GATEWAY_TOKEN"),
      "OPENCLAW_PROBE_TIMEOUT_MS" => System.get_env("OPENCLAW_PROBE_TIMEOUT_MS"),
      "OPENCLAW_WORKSPACE_ROOT" => System.get_env("OPENCLAW_WORKSPACE_ROOT")
    }

    original_load_env_file = Application.get_env(:claw_engine, :load_env_file, true)

    Application.put_env(:claw_engine, :load_env_file, false)

    on_exit(fn ->
      Application.put_env(:claw_engine, :load_env_file, original_load_env_file)

      Enum.each(original, fn {key, value} ->
        if value do
          System.put_env(key, value)
        else
          System.delete_env(key)
        end
      end)
    end)

    :ok
  end

  test "builds the gateway config from environment variables" do
    System.put_env("ENGINE_CONFIG_ROOT", "/tmp/openclaw-engine")
    System.put_env("OPENCLAW_GATEWAY_URL", "wss://gateway.example.com/ws")
    System.put_env("OPENCLAW_GATEWAY_TOKEN", "secret-token")
    System.put_env("OPENCLAW_PROBE_TIMEOUT_MS", "2500")

    gateway = Config.openclaw_gateway()

    assert gateway.token == "secret-token"
    assert gateway.token_present?
    assert gateway.endpoint.scheme == :wss
    assert gateway.endpoint.host == "gateway.example.com"
    assert gateway.endpoint.port == 443
    assert gateway.endpoint.path == "/ws"
    assert Config.openclaw_probe_timeout_ms() == 2_500
    assert Config.engine_config_root() == "/tmp/openclaw-engine"
  end

  test "falls back to defaults when values are missing or invalid" do
    System.put_env("HOME", "/tmp/test-home")
    System.delete_env("OPENCLAW_GATEWAY_URL")
    System.delete_env("OPENCLAW_GATEWAY_TOKEN")
    System.put_env("OPENCLAW_PROBE_TIMEOUT_MS", "bad-value")
    System.delete_env("OPENCLAW_WORKSPACE_ROOT")

    gateway = Config.openclaw_gateway()

    refute gateway.token_present?
    assert gateway.token == nil
    assert gateway.endpoint.scheme == :ws
    assert gateway.endpoint.host == "127.0.0.1"
    assert gateway.endpoint.port == 18_789
    assert gateway.endpoint.path == "/"
    assert Config.openclaw_probe_timeout_ms() == 1_500
    assert Config.openclaw_workspace_root() == "/tmp/test-home/.openclaw/workspace/spaces"
  end

  test "prefers explicit workspace root override" do
    System.put_env("HOME", "/tmp/test-home")
    System.put_env("OPENCLAW_WORKSPACE_ROOT", "/tmp/explicit-root")

    assert Config.openclaw_workspace_root() == "/tmp/explicit-root"
  end
end
