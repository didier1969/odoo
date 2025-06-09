defmodule JobShopScheduler.MixProject do
  use Mix.Project

  def project do
    [
      app: :jss,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {JSS.Application, []}
    ]
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.10"},
      {:postgrex, "~> 0.17"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.2"},
      {:phoenix_pubsub, "~> 2.1"},
      {:plug_cowboy, "~> 2.5"},
      {:plug, "~> 1.14"},
      {:cors_plug, "~> 3.0"}
    ]
  end
end
