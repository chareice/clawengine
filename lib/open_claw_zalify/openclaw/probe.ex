defmodule OpenClawZalify.OpenClaw.Probe do
  @moduledoc """
  Lightweight reachability probe for the OpenClaw Gateway.

  This is intentionally a transport-level probe. It validates that the gateway
  is reachable from the Elixir service and that a control-plane token is
  configured, without implementing the full WebSocket RPC handshake yet.
  """

  alias OpenClawZalify.OpenClaw.Endpoint

  @callback check(Endpoint.t(), keyword()) :: {:ok, map()} | {:error, map()}

  @tcp_socket_opts [:binary, active: false]
  @ssl_socket_opts [:binary, active: false, verify: :verify_none]

  @spec check(Endpoint.t(), keyword()) :: {:ok, map()} | {:error, map()}
  def check(%Endpoint{} = endpoint, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 1_500)

    with {:ok, socket} <- connect(endpoint, timeout) do
      close(endpoint, socket)

      {:ok,
       %{
         host: endpoint.host,
         port: endpoint.port,
         scheme: endpoint.scheme,
         path: endpoint.path,
         reachable: true
       }}
    else
      {:error, reason} ->
        {:error,
         %{
           host: endpoint.host,
           port: endpoint.port,
           scheme: endpoint.scheme,
           path: endpoint.path,
           reachable: false,
           reason: format_reason(reason)
         }}
    end
  end

  defp connect(%Endpoint{scheme: scheme, host: host, port: port}, timeout)
       when scheme in [:ws, :http] do
    :gen_tcp.connect(String.to_charlist(host), port, @tcp_socket_opts, timeout)
  end

  defp connect(%Endpoint{scheme: scheme, host: host, port: port}, timeout)
       when scheme in [:wss, :https] do
    :ssl.connect(String.to_charlist(host), port, @ssl_socket_opts, timeout)
  end

  defp close(%Endpoint{scheme: scheme}, socket) when scheme in [:ws, :http] do
    :gen_tcp.close(socket)
  end

  defp close(%Endpoint{scheme: scheme}, socket) when scheme in [:wss, :https] do
    :ssl.close(socket)
  end

  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason), do: inspect(reason)
end
