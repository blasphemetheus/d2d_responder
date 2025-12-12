defmodule Mix.Tasks.Tui do
  @moduledoc """
  Starts the D2D Responder TUI.

  Usage: mix tui [--echo]

  Options:
    --echo    Auto-connect LoRa and start echo mode
  """
  use Mix.Task

  @shortdoc "Start D2D Responder TUI"

  @impl Mix.Task
  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    # Check for --echo flag - connect and start echo before TUI
    if "--echo" in args do
      IO.puts("Connecting to LoRa and starting echo mode...")
      case D2dResponder.LoRa.connect("/dev/ttyACM0") do
        :ok ->
          D2dResponder.LoRa.send_command("mac pause", 5_000)
          D2dResponder.Echo.start_echo(prefix: "ECHO:")
          IO.puts("Echo mode active!")
        {:error, reason} ->
          IO.puts("Failed to connect LoRa: #{inspect(reason)}")
      end
    end

    # Run TUI (blocks until quit)
    D2dResponder.TUI.run()

    # Keep running after TUI exits
    Process.sleep(:infinity)
  end
end
