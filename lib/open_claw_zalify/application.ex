defmodule OpenClawZalify.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    OpenClawZalify.start_link()
  end
end
