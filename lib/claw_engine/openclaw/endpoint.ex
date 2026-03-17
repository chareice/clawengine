defmodule ClawEngine.OpenClaw.Endpoint do
  @moduledoc """
  Parsed OpenClaw Gateway endpoint information.
  """

  @enforce_keys [:scheme, :host, :port, :path]
  defstruct [:scheme, :host, :port, :path]

  @type scheme :: :ws | :wss | :http | :https

  @type t :: %__MODULE__{
          scheme: scheme(),
          host: String.t(),
          port: pos_integer(),
          path: String.t()
        }

  @spec parse!(String.t()) :: t()
  def parse!(url) when is_binary(url) do
    uri = URI.parse(url)

    scheme =
      case uri.scheme do
        "ws" -> :ws
        "wss" -> :wss
        "http" -> :http
        "https" -> :https
        other -> raise ArgumentError, "unsupported OpenClaw gateway scheme: #{inspect(other)}"
      end

    %__MODULE__{
      scheme: scheme,
      host: uri.host || raise(ArgumentError, "OpenClaw gateway host is required"),
      port: uri.port || default_port(scheme),
      path: normalize_path(uri.path)
    }
  end

  defp default_port(:ws), do: 80
  defp default_port(:http), do: 80
  defp default_port(:wss), do: 443
  defp default_port(:https), do: 443

  defp normalize_path(nil), do: "/"
  defp normalize_path(""), do: "/"
  defp normalize_path(path), do: path
end
