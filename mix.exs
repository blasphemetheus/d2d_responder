defmodule D2dResponder.MixProject do
  use Mix.Project

  def project do
    [
      app: :d2d_responder,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {D2dResponder.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:circuits_uart, "~> 1.5"},
      {:circuits_spi, "~> 2.0"},
      {:circuits_gpio, "~> 2.0"},
      {:jason, "~> 1.4"},
      {:owl, "~> 0.12"}
    ]
  end
end
