defmodule D2dResponder.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      D2dResponder.FileLogger,
      D2dResponder.LoRa,
      D2dResponder.Beacon,
      D2dResponder.Echo,
      # Network services (auto-start for field testing)
      D2dResponder.Network.WiFi,
      D2dResponder.Network.Bluetooth,
      D2dResponder.Network.Responder
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: D2dResponder.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
