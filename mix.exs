defmodule Siri.MixProject do
  use Mix.Project

  def project do
    [
      app: :siri,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: true,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Siri.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:nostrum, "~> 0.10"}
      {:nostrum, github: "Kraigie/nostrum"},
      {:ex_llm, "~> 0.8.1"}
    ]
  end
end
