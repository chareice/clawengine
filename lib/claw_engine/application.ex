defmodule ClawEngine.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    ClawEngine.start_link()
  end
end
