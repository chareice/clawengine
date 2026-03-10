defmodule OpenClawZalify.Config do
  @moduledoc """
  Runtime configuration helpers for the local control-plane service.
  """

  alias OpenClawZalify.EnvFile
  alias OpenClawZalify.OpenClaw.Endpoint

  @default_http_port 4000
  @default_admin_timeout_ms 5_000
  @default_chat_timeout_ms 60_000
  @default_probe_timeout_ms 1_500
  @default_gateway_url "ws://127.0.0.1:18789"
  @default_workspace_root "/home/node/.openclaw/workspace/spaces"

  @spec http_port() :: pos_integer()
  def http_port do
    load_dotenv()
    Application.get_env(:openclaw_zalify, :http_port, @default_http_port)
  end

  @spec openclaw_admin_timeout_ms() :: pos_integer()
  def openclaw_admin_timeout_ms do
    load_dotenv()

    System.get_env("OPENCLAW_ADMIN_TIMEOUT_MS", Integer.to_string(@default_admin_timeout_ms))
    |> parse_positive_integer(@default_admin_timeout_ms)
  end

  @spec openclaw_chat_timeout_ms() :: pos_integer()
  def openclaw_chat_timeout_ms do
    load_dotenv()

    System.get_env("OPENCLAW_CHAT_TIMEOUT_MS", Integer.to_string(@default_chat_timeout_ms))
    |> parse_positive_integer(@default_chat_timeout_ms)
  end

  @spec openclaw_probe_timeout_ms() :: pos_integer()
  def openclaw_probe_timeout_ms do
    load_dotenv()

    System.get_env("OPENCLAW_PROBE_TIMEOUT_MS", Integer.to_string(@default_probe_timeout_ms))
    |> parse_positive_integer(@default_probe_timeout_ms)
  end

  @spec openclaw_gateway() :: %{
          endpoint: Endpoint.t(),
          token: String.t() | nil,
          token_present?: boolean()
        }
  def openclaw_gateway do
    load_dotenv()
    token = System.get_env("OPENCLAW_GATEWAY_TOKEN")

    %{
      endpoint:
        System.get_env("OPENCLAW_GATEWAY_URL", @default_gateway_url)
        |> Endpoint.parse!(),
      token: blank_to_nil(token),
      token_present?: present?(token)
    }
  end

  @spec openclaw_gateway_ws_url() :: String.t()
  def openclaw_gateway_ws_url do
    gateway = openclaw_gateway()

    "#{gateway.endpoint.scheme}://#{gateway.endpoint.host}:#{gateway.endpoint.port}#{gateway.endpoint.path}"
  end

  @spec openclaw_workspace_root() :: String.t()
  def openclaw_workspace_root do
    load_dotenv()
    System.get_env("OPENCLAW_WORKSPACE_ROOT", @default_workspace_root)
  end

  @spec engine_config_root() :: String.t()
  def engine_config_root do
    load_dotenv()

    System.get_env(
      "ENGINE_CONFIG_ROOT",
      Path.join(List.to_string(:code.priv_dir(:openclaw_zalify)), "engine/default")
    )
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

  defp load_dotenv do
    if Mix.env() != :test do
      EnvFile.load_system(EnvFile.default_path())
    end
  end
end
