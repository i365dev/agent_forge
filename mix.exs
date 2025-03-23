defmodule AgentForge.MixProject do
  use Mix.Project

  def project do
    [
      app: :agent_forge,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # Add test coverage configuration
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {AgentForge.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:excoveralls, "~> 0.18", only: :test},
      {:yaml_elixir, "~> 2.9"},  # YAML support
      {:meck, "~> 0.9", only: :test}  # For mocking in tests
    ]
  end
end
