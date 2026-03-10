defmodule OpenClawZalify.MixProject do
  use Mix.Project

  def project do
    [
      app: :openclaw_zalify,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {OpenClawZalify.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:bandit, "~> 1.5"},
      {:ecto_sql, "~> 3.12"},
      {:jason, "~> 1.4"},
      {:plug, "~> 1.16"},
      {:postgrex, "~> 0.19"},
      {:websock_adapter, "~> 0.5"},
      {:websockex, "~> 0.4.3"},
      {:yaml_elixir, "~> 2.11"}
    ]
  end
end
