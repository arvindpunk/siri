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
      {:ecto, "~> 3.10"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, "~> 0.21"},
      {:req, "~> 0.5.0"},
      {:ex_llm, github: "arvindpunk/ex_llm", branch: "fix/structured-response"},
      {:instructor, "~> 0.1"},
      {:nostrum, github: "Kraigie/nostrum"}
    ]
  end
end
