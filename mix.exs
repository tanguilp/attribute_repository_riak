defmodule AttributeRepositoryRiak.MixProject do
  use Mix.Project

  def project do
    [
      app: :attribute_repository_riak,
      version: "0.2.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: [
        main: "readme",
        extras: ["README.md"]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:attribute_repository, github: "tanguilp/attribute_repository", tag: "v0.2.0"},
      {:riak, github: "tanguilp/riak-elixir-client"},
      {:dialyxir, "~> 1.0.0-rc.4", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.19", only: :dev, runtime: false}
    ]
  end
end
