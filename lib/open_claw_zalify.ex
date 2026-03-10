defmodule OpenClawZalify do
  @moduledoc """
  ClawEngine bootstrap for OpenClaw integration.
  """

  @version Mix.Project.config()[:version]

  @doc """
  Returns the application version.
  """
  @spec version() :: String.t()
  def version do
    to_string(@version)
  end
end
