defmodule Mix.Tasks.Openclaw.Probe do
  @shortdoc "Checks whether the configured OpenClaw Gateway is reachable"
  @moduledoc """
  Runs a transport-level probe against the configured OpenClaw Gateway.
  """

  use Mix.Task

  alias ClawEngine.Config
  alias ClawEngine.OpenClaw.Probe

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("loadpaths")
    Mix.Task.run("compile")

    gateway = Config.openclaw_gateway()

    if gateway.token_present? do
      case Probe.check(gateway.endpoint, timeout: Config.openclaw_probe_timeout_ms()) do
        {:ok, details} ->
          Mix.shell().info(
            "OpenClaw gateway reachable at #{details.scheme}://#{details.host}:#{details.port}"
          )

        {:error, details} ->
          Mix.raise(
            "OpenClaw gateway is not reachable at #{details.scheme}://#{details.host}:#{details.port} (#{details.reason})"
          )
      end
    else
      Mix.raise("OPENCLAW_GATEWAY_TOKEN is missing")
    end
  end
end
