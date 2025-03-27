defmodule AgentForge.MixProject do
  use Mix.Project

  @source_url "https://github.com/USERNAME/agent_forge"
  @version "0.2.1"

  def project do
    [
      app: :agent_forge,
      version: @version,
      elixir: "~> 1.18.3",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: ["lib"],
      # Test coverage configuration
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.github": :test
      ],
      # Hex.pm package configuration
      description: "A lightweight, signal-driven workflow framework for building dynamic systems",
      package: package(),
      # Documentation configuration
      name: "AgentForge",
      docs: docs(),
      homepage_url: @source_url,
      source_url: @source_url
    ]
  end

  def application do
    [
      mod: {AgentForge.Application, []},
      extra_applications: [:logger, :crypto, :yaml_elixir, :jason],
      env: [default_store_name: AgentForge.Store]
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:excoveralls, "~> 0.18", only: :test},
      # YAML support
      {:yaml_elixir, "~> 2.9"},
      # For mocking in tests
      {:meck, "~> 0.9", only: :test},
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},
      # Code quality and static analysis
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      # Optional dependencies for plugins
      {:finch, "~> 0.16", optional: true}
    ]
  end

  defp package do
    [
      name: "agent_forge",
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md),
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"] ++ Path.wildcard("guides/*.md"),
      extra_section: "GUIDES",
      groups_for_extras: [
        Guides: Path.wildcard("guides/*.md")
      ],
      groups_for_modules: [
        Core: [
          AgentForge,
          AgentForge.Signal,
          AgentForge.Flow,
          AgentForge.Store
        ],
        Primitives: [
          AgentForge.Primitives
        ],
        "Dynamic Flows": [
          AgentForge.DynamicFlow
        ],
        Configuration: [
          AgentForge.Config
        ],
        Utilities: [
          AgentForge.Debug,
          AgentForge.Tools,
          AgentForge.Runtime
        ]
      ],
      source_url: @source_url,
      source_ref: "v#{@version}"
    ]
  end
end
