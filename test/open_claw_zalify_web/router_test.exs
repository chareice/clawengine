defmodule OpenClawZalifyWeb.RouterTest do
  use ExUnit.Case, async: false
  import Plug.Test

  alias OpenClawZalifyWeb.Router

  defmodule SuccessProbe do
    def check(endpoint, _opts) do
      {:ok,
       %{
         host: endpoint.host,
         port: endpoint.port,
         scheme: endpoint.scheme,
         path: endpoint.path,
         reachable: true
       }}
    end
  end

  defmodule FailureProbe do
    def check(endpoint, _opts) do
      {:error,
       %{
         host: endpoint.host,
         port: endpoint.port,
         scheme: endpoint.scheme,
         path: endpoint.path,
         reachable: false,
         reason: "econnrefused"
       }}
    end
  end

  setup do
    original_probe = Application.get_env(:openclaw_zalify, :openclaw_probe)

    original_env = %{
      "OPENCLAW_GATEWAY_URL" => System.get_env("OPENCLAW_GATEWAY_URL"),
      "OPENCLAW_GATEWAY_TOKEN" => System.get_env("OPENCLAW_GATEWAY_TOKEN")
    }

    on_exit(fn ->
      Application.put_env(:openclaw_zalify, :openclaw_probe, original_probe)

      Enum.each(original_env, fn {key, value} ->
        if value do
          System.put_env(key, value)
        else
          System.delete_env(key)
        end
      end)
    end)

    :ok
  end

  test "GET /health returns service metadata" do
    conn =
      :get
      |> conn("/health")
      |> Router.call([])

    assert conn.status == 200

    body = Jason.decode!(conn.resp_body)

    assert body["status"] == "ok"
    assert body["service"] == "clawengine"
  end

  test "GET /ready returns not ready when the gateway token is missing" do
    System.put_env("OPENCLAW_GATEWAY_URL", "ws://127.0.0.1:18789")
    System.delete_env("OPENCLAW_GATEWAY_TOKEN")
    Application.put_env(:openclaw_zalify, :openclaw_probe, SuccessProbe)

    conn =
      :get
      |> conn("/ready")
      |> Router.call([])

    assert conn.status == 503

    body = Jason.decode!(conn.resp_body)

    assert body["status"] == "not_ready"
    assert body["reason"] == "missing_gateway_token"
  end

  test "GET /ready returns ready when the probe succeeds" do
    System.put_env("OPENCLAW_GATEWAY_URL", "ws://127.0.0.1:18789")
    System.put_env("OPENCLAW_GATEWAY_TOKEN", "secret-token")
    Application.put_env(:openclaw_zalify, :openclaw_probe, SuccessProbe)

    conn =
      :get
      |> conn("/ready")
      |> Router.call([])

    assert conn.status == 200

    body = Jason.decode!(conn.resp_body)

    assert body["status"] == "ready"
    assert body["gateway"]["reachable"] == true
  end

  test "GET /ready returns not ready when the probe fails" do
    System.put_env("OPENCLAW_GATEWAY_URL", "ws://127.0.0.1:18789")
    System.put_env("OPENCLAW_GATEWAY_TOKEN", "secret-token")
    Application.put_env(:openclaw_zalify, :openclaw_probe, FailureProbe)

    conn =
      :get
      |> conn("/ready")
      |> Router.call([])

    assert conn.status == 503

    body = Jason.decode!(conn.resp_body)

    assert body["status"] == "not_ready"
    assert body["reason"] == "gateway_unreachable"
    assert body["gateway"]["reason"] == "econnrefused"
  end
end
