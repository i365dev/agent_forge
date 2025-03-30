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
      aliases: aliases(),
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

  defp aliases do
    [
      # Run standard tests and then run examples
      test: ["test", &run_examples/1],
      # Run only the examples files
      "test.examples": [&run_examples/1],
      lint: ["format", "credo --strict"]
    ]
  end

  # Custom function to run all example files in the examples directory
  defp run_examples(_) do
    IO.puts("\n=== Running examples ===\n")

    # Find all .exs files in the examples directory
    examples = Path.wildcard("examples/**/*.exs")

    # Run each example file
    Enum.each(examples, fn example_file ->
      relative_path = Path.relative_to_cwd(example_file)
      IO.puts("Running example: #{relative_path}")

      try do
        # Capture output to avoid cluttering the test results
        ExUnit.CaptureIO.capture_io(fn ->
          Code.eval_file(example_file)
        end)

        IO.puts("✓ Example #{relative_path} completed successfully\n")
      rescue
        e ->
          IO.puts("✗ Example #{relative_path} failed with error: #{inspect(e)}\n")
          Mix.raise("Example failed: #{relative_path}")
      end
    end)

    IO.puts("=== Finished running examples ===\n")
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
