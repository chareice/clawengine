defmodule OpenClawZalify.Config do
  @moduledoc """
  Runtime configuration helpers for the local control-plane service.
  """

  alias OpenClawZalify.OpenClaw.Endpoint

  @default_http_port 4000
  @default_probe_timeout_ms 1_500
  @default_gateway_url "ws://127.0.0.1:18789"

  @spec http_port() :: pos_integer()
  def http_port do
    Application.get_env(:openclaw_zalify, :http_port, @default_http_port)
  end

  @spec openclaw_probe_timeout_ms() :: pos_integer()
  def openclaw_probe_timeout_ms do
    System.get_env("OPENCLAW_PROBE_TIMEOUT_MS", Integer.to_string(@default_probe_timeout_ms))
    |> parse_positive_integer(@default_probe_timeout_ms)
  end

  @spec openclaw_gateway() :: %{
          endpoint: Endpoint.t(),
          token: String.t() | nil,
          token_present?: boolean()
        }
  def openclaw_gateway do
    token = System.get_env("OPENCLAW_GATEWAY_TOKEN")

    %{
      endpoint:
        System.get_env("OPENCLAW_GATEWAY_URL", @default_gateway_url)
        |> Endpoint.parse!(),
      token: blank_to_nil(token),
      token_present?: present?(token)
    }
  end

  @spec present?(String.t() | nil) :: boolean()
  def present?(value) when is_binary(value), do: String.trim(value) != ""
  def present?(_value), do: false

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_value), do: nil

  defp parse_positive_integer(value, fallback) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _other -> fallback
    end
  end
end
