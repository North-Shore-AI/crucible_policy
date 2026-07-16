defmodule CruciblePolicy.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/North-Shore-AI/crucible_policy"

  def project do
    [
      app: :crucible_policy,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      name: "CruciblePolicy",
      description:
        "Routing, gating, fusion, uncertainty, verifier, memory, and steering contracts",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def cli do
    [
      preferred_envs: [
        ci: :test,
        docs: :dev
      ]
    ]
  end

  defp deps do
    [
      {:crucible_signal, path: "../crucible_signal"},
      {:crucible_signal_trace, path: "../crucible_signal_trace"},
      {:jason, "~> 1.4"},
      {:nx, "~> 0.12.1"},
      {:ex_doc, "~> 0.40.3", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      ci: [
        "deps.get",
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test",
        "docs"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"] ++ Path.wildcard("guides/*.md"),
      groups_for_extras: [
        Guides: Path.wildcard("guides/*.md")
      ],
      source_ref: "main",
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  defp package do
    [
      name: "crucible_policy",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib assets guides examples mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end
end
