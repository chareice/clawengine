defmodule OpenClawZalifyWeb.Router do
  @moduledoc false

  use Plug.Router

  alias OpenClawZalify.Config
  alias OpenClawZalify.OpenClaw.Probe

  plug(Plug.Logger)
  plug(:match)
  plug(Plug.Parsers, parsers: [:json], pass: ["application/json"], json_decoder: Jason)
  plug(:dispatch)

  get "/health" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      200,
      Jason.encode!(%{
        status: "ok",
        service: "openclaw-zalify",
        version: OpenClawZalify.version()
      })
    )
  end

  get "/ready" do
    gateway = Config.openclaw_gateway()

    case readiness(gateway) do
      {:ok, payload} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(payload))

      {:error, payload} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(503, Jason.encode!(payload))
    end
  end

  match _ do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "not_found"}))
  end

  defp readiness(%{endpoint: endpoint, token_present?: false}) do
    {:error,
     %{
       status: "not_ready",
       reason: "missing_gateway_token",
       gateway: %{
         url: "#{endpoint.scheme}://#{endpoint.host}:#{endpoint.port}#{endpoint.path}"
       }
     }}
  end

  defp readiness(%{endpoint: endpoint, token_present?: true}) do
    probe = Application.get_env(:openclaw_zalify, :openclaw_probe, Probe)

    case probe.check(endpoint, timeout: Config.openclaw_probe_timeout_ms()) do
      {:ok, details} ->
        {:ok,
         %{
           status: "ready",
           gateway: details
         }}

      {:error, details} ->
        {:error,
         %{
           status: "not_ready",
           reason: "gateway_unreachable",
           gateway: details
         }}
    end
  end
end
