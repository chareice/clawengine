defmodule OpenClawZalify.OpenClaw.EndpointTest do
  use ExUnit.Case, async: true

  alias OpenClawZalify.OpenClaw.Endpoint

  test "parses explicit port and path" do
    endpoint = Endpoint.parse!("ws://127.0.0.1:18789/ws")

    assert endpoint.scheme == :ws
    assert endpoint.host == "127.0.0.1"
    assert endpoint.port == 18_789
    assert endpoint.path == "/ws"
  end

  test "defaults the path and port from scheme" do
    endpoint = Endpoint.parse!("https://gateway.example.com")

    assert endpoint.scheme == :https
    assert endpoint.host == "gateway.example.com"
    assert endpoint.port == 443
    assert endpoint.path == "/"
  end
end
