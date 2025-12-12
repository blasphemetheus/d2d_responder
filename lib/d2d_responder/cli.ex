defmodule D2dResponder.CLI do
  @moduledoc """
  CLI startup handler for D2D Responder.

  Parses command-line arguments and starts the appropriate mode:
  - `--echo` or `-e`: Auto-connect LoRa and start echo mode
  - `--tui` or no args: Start interactive TUI

  ## Usage

      # Start with TUI (default)
      iex -S mix

      # Start in echo mode (for field testing)
      iex -S mix -- --echo
      iex -S mix -- -e
  """

  alias D2dResponder.{LoRa, Echo, TUI}

  @doc """
  Parse args and start the appropriate mode.
  Called after application supervisor starts.
  """
  def start do
    args = System.argv()

    cond do
      "--echo" in args or "-e" in args ->
        start_echo_mode()

      "--help" in args or "-h" in args ->
        print_help()

      true ->
        start_tui()
    end
  end

  defp start_echo_mode do
    IO.puts("\n")
    IO.puts("═══════════════════════════════════════")
    IO.puts("  D2D Responder - Echo Mode")
    IO.puts("═══════════════════════════════════════")
    IO.puts("")

    # Give services time to initialize
    Process.sleep(500)

    IO.write("Connecting to LoRa module... ")
    case LoRa.connect("/dev/ttyACM0") do
      :ok ->
        IO.puts("OK")

        # Pause MAC for raw radio
        IO.write("Pausing MAC layer... ")
        case LoRa.send_command("mac pause", 5_000) do
          {:ok, _} -> IO.puts("OK")
          _ -> IO.puts("(skipped)")
        end

        # Start echo mode
        IO.write("Starting echo mode... ")
        case Echo.start_echo(prefix: "ECHO:") do
          :ok ->
            IO.puts("OK")
            IO.puts("")
            IO.puts("Listening for LoRa messages...")
            IO.puts("Received messages will be echoed with 'ECHO:' prefix")
            IO.puts("")
            IO.puts("Press Ctrl+C twice to exit")
            IO.puts("")

            # Keep running and show stats periodically
            monitor_echo()

          {:error, reason} ->
            IO.puts("FAILED: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("FAILED")
        IO.puts("Could not connect to LoRa module: #{inspect(reason)}")
        IO.puts("")
        IO.puts("Make sure the LoRa module is connected to /dev/ttyACM0")
    end
  end

  defp start_tui do
    # Small delay to let services initialize
    Process.sleep(300)
    # Just run TUI - it handles stdin errors gracefully
    TUI.run()
  end

  defp print_help do
    IO.puts("""

    D2D Responder - LoRa Field Testing Tool

    Usage:
      iex -S mix [-- OPTIONS]

    Options:
      --echo, -e    Start in echo mode (auto-connect and listen)
      --tui         Start interactive TUI (default)
      --help, -h    Show this help message

    Examples:
      iex -S mix              # Start TUI
      iex -S mix -- --echo    # Start in echo mode
      iex -S mix -- -e        # Start in echo mode (short flag)

    """)
  end

  defp monitor_echo do
    # Show status every 30 seconds
    Process.sleep(30_000)

    status = Echo.status()
    if status.running do
      IO.puts("[Echo] RX: #{status.rx_count}, TX: #{status.tx_count}")
      monitor_echo()
    end
  end
end
