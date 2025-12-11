defmodule D2dResponder.TUI do
  @moduledoc """
  Terminal UI for D2D Responder using Owl.
  Run with: D2dResponder.TUI.run()
  """

  alias D2dResponder.Network.{WiFi, Bluetooth, Responder}
  alias D2dResponder.{LoRa, Beacon, Echo}

  @menu_items [
    {"1", "Start All Network Services", :start_all},
    {"2", "Stop All Network Services", :stop_all},
    {"3", "Reset All (cleanup)", :reset_all},
    {"4", "WiFi: Start Ad-hoc", :wifi_start},
    {"5", "WiFi: Stop Ad-hoc", :wifi_stop},
    {"6", "WiFi: Reset", :wifi_reset},
    {"7", "Bluetooth: Start NAP Server", :bt_start},
    {"8", "Bluetooth: Stop NAP Server", :bt_stop},
    {"9", "Bluetooth: Reset", :bt_reset},
    {"i", "iperf3: Restart Server", :iperf_restart},
    {"l", "LoRa: Connect", :lora_connect},
    {"e", "LoRa: Start Echo Mode", :lora_echo},
    {"b", "LoRa: Start Beacon Mode", :lora_beacon},
    {"x", "LoRa: Stop Echo/Beacon", :lora_stop},
    {"s", "Show Status", :status},
    {"q", "Quit", :quit}
  ]

  def run do
    puts_colored("\n═══ D2D Responder Control Panel ═══\n", :cyan)
    loop()
  end

  defp puts_colored(text, color) do
    text |> Owl.Data.tag(color) |> Owl.Data.to_chardata() |> IO.puts()
  end

  defp loop do
    print_status()
    print_menu()

    case get_input() do
      :quit ->
        puts_colored("\nGoodbye!\n", :yellow)
        :ok

      action ->
        execute_action(action)
        IO.puts("")
        loop()
    end
  end

  defp print_status do
    wifi_status = get_wifi_status()
    bt_status = get_bt_status()
    iperf_status = get_iperf_status()
    lora_status = get_lora_status()

    puts_colored("── Status ──", :blue)

    # LoRa status
    lora_badge = if lora_status.connected, do: status_badge("UP", :green), else: status_badge("DOWN", :red)
    lora_mode = cond do
      lora_status.echo_running -> "Echo"
      lora_status.beacon_running -> "Beacon"
      lora_status.connected -> "Idle"
      true -> "N/A"
    end
    IO.puts("  LoRa:      #{lora_badge}  #{lora_mode}")

    # WiFi status
    wifi_badge = if wifi_status.connected, do: status_badge("UP", :green), else: status_badge("DOWN", :red)
    IO.puts("  WiFi:      #{wifi_badge}  #{wifi_status.interface} @ #{wifi_status.ip}")

    # Bluetooth status
    bt_badge = if bt_status.connected, do: status_badge("UP", :green), else: status_badge("DOWN", :red)
    IO.puts("  Bluetooth: #{bt_badge}  #{bt_status.interface} @ #{bt_status.ip}")

    # iperf3 status
    iperf_badge = if iperf_status.running, do: status_badge("UP", :green), else: status_badge("DOWN", :red)
    iperf_port = if iperf_status.port, do: "port #{iperf_status.port}", else: "not running"
    IO.puts("  iperf3:    #{iperf_badge}  #{iperf_port}")

    IO.puts("")
  end

  defp status_badge(text, color) do
    Owl.Data.tag("[#{text}]", color) |> Owl.Data.to_chardata() |> IO.iodata_to_binary()
  end

  defp print_menu do
    puts_colored("── Actions ──", :blue)

    Enum.each(@menu_items, fn {key, label, _action} ->
      key_str = Owl.Data.tag("[#{key}]", :yellow) |> Owl.Data.to_chardata() |> IO.iodata_to_binary()
      IO.puts("  #{key_str} #{label}")
    end)

    IO.puts("")
  end

  defp get_input do
    IO.write(Owl.Data.tag("Select option: ", :cyan) |> Owl.Data.to_chardata())
    input =
      IO.gets("")
      |> String.trim()
      |> String.downcase()

    case Enum.find(@menu_items, fn {key, _, _} -> key == input end) do
      {_, _, action} -> action
      nil ->
        puts_colored("Invalid option, try again.", :red)
        get_input()
    end
  end

  defp execute_action(:start_all) do
    puts_colored("\nStarting all network services...", :cyan)

    with_spinner("Starting WiFi ad-hoc...", fn -> WiFi.setup() end)
    with_spinner("Starting Bluetooth NAP...", fn -> Bluetooth.start_server() end)
    with_spinner("Starting iperf3...", fn -> Responder.start_iperf_server() end)

    puts_colored("✓ All services started!", :green)
  end

  defp execute_action(:stop_all) do
    puts_colored("\nStopping all network services...", :cyan)

    with_spinner("Stopping WiFi...", fn -> WiFi.teardown() end)
    with_spinner("Stopping Bluetooth...", fn -> Bluetooth.stop_server() end)
    with_spinner("Stopping iperf3...", fn -> Responder.stop_iperf_server() end)

    puts_colored("✓ All services stopped!", :green)
  end

  defp execute_action(:reset_all) do
    puts_colored("\nResetting all network services...", :cyan)

    with_spinner("Resetting WiFi...", fn -> WiFi.reset() end)
    with_spinner("Resetting Bluetooth...", fn -> Bluetooth.reset() end)
    with_spinner("Restarting iperf3...", fn ->
      Responder.stop_iperf_server()
      Responder.start_iperf_server()
    end)

    puts_colored("✓ All services reset!", :green)
  end

  defp execute_action(:wifi_start) do
    with_spinner("Starting WiFi ad-hoc...", fn -> WiFi.setup() end)
    |> print_result("WiFi")
  end

  defp execute_action(:wifi_stop) do
    with_spinner("Stopping WiFi...", fn -> WiFi.teardown() end)
    |> print_result("WiFi")
  end

  defp execute_action(:wifi_reset) do
    with_spinner("Resetting WiFi...", fn -> WiFi.reset() end)
    |> print_result("WiFi")
  end

  defp execute_action(:bt_start) do
    with_spinner("Starting Bluetooth NAP server...", fn -> Bluetooth.start_server() end)
    |> print_result("Bluetooth")
  end

  defp execute_action(:bt_stop) do
    with_spinner("Stopping Bluetooth NAP server...", fn -> Bluetooth.stop_server() end)
    |> print_result("Bluetooth")
  end

  defp execute_action(:bt_reset) do
    with_spinner("Resetting Bluetooth...", fn -> Bluetooth.reset() end)
    |> print_result("Bluetooth")
  end

  defp execute_action(:iperf_restart) do
    with_spinner("Restarting iperf3 server...", fn ->
      Responder.stop_iperf_server()
      Process.sleep(500)
      Responder.start_iperf_server()
    end)
    |> print_result("iperf3")
  end

  defp execute_action(:lora_connect) do
    IO.write("  Connecting to LoRa module... ")

    case LoRa.connect("/dev/ttyACM0") do
      :ok ->
        puts_colored("✓", :green)
        # Give the module time to initialize after connect
        Process.sleep(500)
        # pause_mac can be slow - try it but don't fail if it times out
        IO.write("  Pausing MAC layer... ")
        case LoRa.send_command("mac pause", 5_000) do
          {:ok, response} ->
            puts_colored("✓ (#{response})", :green)
          {:error, :timeout} ->
            puts_colored("timeout (may already be paused)", :yellow)
          {:error, reason} ->
            puts_colored("#{inspect(reason)}", :yellow)
        end
        puts_colored("LoRa ready.", :green)

      {:error, reason} ->
        puts_colored("✗", :red)
        puts_colored("LoRa connect failed: #{inspect(reason)}", :red)
    end
  end

  defp execute_action(:lora_echo) do
    cond do
      not LoRa.connected?() ->
        puts_colored("LoRa not connected. Connect first with 'l'.", :red)

      Echo.status().running ->
        puts_colored("Echo mode is already running.", :yellow)

      Beacon.status().running ->
        puts_colored("Stopping Beacon mode first...", :cyan)
        Beacon.stop_beacon()
        with_spinner("Starting Echo mode...", fn -> Echo.start_echo() end)
        |> print_result("LoRa Echo")

      true ->
        with_spinner("Starting Echo mode...", fn -> Echo.start_echo() end)
        |> print_result("LoRa Echo")
    end
  end

  defp execute_action(:lora_beacon) do
    cond do
      not LoRa.connected?() ->
        puts_colored("LoRa not connected. Connect first with 'l'.", :red)

      Beacon.status().running ->
        puts_colored("Beacon mode is already running.", :yellow)

      Echo.status().running ->
        puts_colored("Stopping Echo mode first...", :cyan)
        Echo.stop_echo()
        with_spinner("Starting Beacon mode...", fn -> Beacon.start_beacon() end)
        |> print_result("LoRa Beacon")

      true ->
        with_spinner("Starting Beacon mode...", fn -> Beacon.start_beacon() end)
        |> print_result("LoRa Beacon")
    end
  end

  defp execute_action(:lora_stop) do
    echo_status = Echo.status()
    beacon_status = Beacon.status()

    cond do
      echo_status.running ->
        with_spinner("Stopping Echo mode (RX: #{echo_status.rx_count}, TX: #{echo_status.tx_count})...", fn ->
          Echo.stop_echo()
        end)
        |> print_result("LoRa Echo")

      beacon_status.running ->
        with_spinner("Stopping Beacon mode (TX: #{beacon_status.tx_count})...", fn ->
          Beacon.stop_beacon()
        end)
        |> print_result("LoRa Beacon")

      true ->
        puts_colored("No LoRa mode is currently running.", :yellow)
    end
  end

  defp execute_action(:status) do
    puts_colored("\n── Detailed Status ──", :blue)

    lora = get_lora_status()
    IO.puts("\nLoRa:")
    IO.puts("  Connected: #{lora.connected}")
    IO.puts("  Echo Running: #{lora.echo_running}")
    if lora.echo_running do
      IO.puts("    RX Count: #{lora.echo_rx_count}")
      IO.puts("    TX Count: #{lora.echo_tx_count}")
    end
    IO.puts("  Beacon Running: #{lora.beacon_running}")
    if lora.beacon_running do
      IO.puts("    TX Count: #{lora.beacon_tx_count}")
      IO.puts("    Interval: #{lora.beacon_interval}ms")
    end

    wifi = get_wifi_status()
    IO.puts("\nWiFi Ad-hoc:")
    IO.puts("  Connected: #{wifi.connected}")
    IO.puts("  Interface: #{wifi.interface}")
    IO.puts("  IP: #{wifi.ip}")
    IO.puts("  Peer IP: #{wifi.peer_ip}")

    bt = get_bt_status()
    IO.puts("\nBluetooth NAP:")
    IO.puts("  Connected: #{bt.connected}")
    IO.puts("  Mode: #{bt.mode}")
    IO.puts("  Interface: #{bt.interface}")
    IO.puts("  IP: #{bt.ip}")
    IO.puts("  Peer IP: #{bt.peer_ip}")

    iperf = get_iperf_status()
    IO.puts("\niperf3 Server:")
    IO.puts("  Running: #{iperf.running}")
    IO.puts("  Port: #{iperf.port || "N/A"}")
  end

  defp with_spinner(message, func) do
    IO.write("  #{message} ")

    result = func.()

    case result do
      :ok ->
        puts_colored("✓", :green)
        :ok
      {:ok, _} ->
        puts_colored("✓", :green)
        :ok
      {:error, reason} ->
        puts_colored("✗ #{inspect(reason)}", :red)
        {:error, reason}
      other ->
        puts_colored("✓", :green)
        other
    end
  rescue
    e ->
      puts_colored("✗ #{inspect(e)}", :red)
      {:error, e}
  catch
    :exit, {:timeout, _} ->
      puts_colored("✗ timeout", :red)
      {:error, :timeout}
    :exit, reason ->
      puts_colored("✗ exit: #{inspect(reason)}", :red)
      {:error, reason}
  end

  defp print_result(:ok, service), do: puts_colored("#{service} operation completed.", :green)
  defp print_result({:ok, _}, service), do: puts_colored("#{service} operation completed.", :green)
  defp print_result({:error, reason}, service), do: puts_colored("#{service} failed: #{inspect(reason)}", :red)
  defp print_result(_, service), do: puts_colored("#{service} operation completed.", :green)

  defp get_wifi_status do
    try do
      WiFi.get_status()
    rescue
      _ -> %{connected: false, interface: "wlan0", ip: "192.168.12.1", peer_ip: "192.168.12.2"}
    end
  end

  defp get_bt_status do
    try do
      Bluetooth.get_status()
    rescue
      _ -> %{connected: false, mode: :server, interface: "pan0", ip: "192.168.44.1", peer_ip: "192.168.44.2"}
    end
  end

  defp get_iperf_status do
    try do
      Responder.get_status()
    rescue
      _ -> %{running: false, port: nil}
    end
  end

  defp get_lora_status do
    try do
      connected = LoRa.connected?()
      echo_status = Echo.status()
      beacon_status = Beacon.status()

      %{
        connected: connected,
        echo_running: echo_status.running,
        echo_rx_count: echo_status.rx_count,
        echo_tx_count: echo_status.tx_count,
        beacon_running: beacon_status.running,
        beacon_tx_count: beacon_status.tx_count,
        beacon_interval: beacon_status.interval
      }
    rescue
      _ -> %{
        connected: false,
        echo_running: false,
        echo_rx_count: 0,
        echo_tx_count: 0,
        beacon_running: false,
        beacon_tx_count: 0,
        beacon_interval: 0
      }
    end
  end
end
