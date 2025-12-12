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
    {"c", "LoRa: Radio Config", :lora_config},
    {"e", "LoRa: Start Echo Mode", :lora_echo},
    {"b", "LoRa: Start Beacon Mode", :lora_beacon},
    {"x", "LoRa: Stop Echo/Beacon", :lora_stop},
    {"r", "LoRa: Raw Command", :lora_raw},
    {"s", "Show Status", :status},
    {"q", "Quit", :quit}
  ]

  # Radio presets: {name, description, sf, bw, power}
  @radio_presets [
    {"1", "Long Range", "Max distance, slowest speed", 12, 125, 14},
    {"2", "Balanced", "Good range and speed", 9, 125, 14},
    {"3", "Fast", "Short range, fastest speed", 7, 125, 14},
    {"4", "Low Power", "Battery saving mode", 9, 125, 5}
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

    case IO.gets("") do
      {:error, reason} ->
        puts_colored("Input error: #{inspect(reason)}. Try running with: iex --erl \"-noinput\" -S mix", :red)
        Process.sleep(2000)
        get_input()

      :eof ->
        :quit

      input when is_binary(input) ->
        input = input |> String.trim() |> String.downcase()

        case Enum.find(@menu_items, fn {key, _, _} -> key == input end) do
          {_, _, action} -> action
          nil ->
            puts_colored("Invalid option, try again.", :red)
            get_input()
        end
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
        try do
          case LoRa.send_command("mac pause", 5_000) do
            {:ok, response} ->
              puts_colored("✓ (#{response})", :green)
            {:error, :timeout} ->
              puts_colored("timeout (may already be paused)", :yellow)
            {:error, reason} ->
              puts_colored("#{inspect(reason)}", :yellow)
          end
        catch
          :exit, {:timeout, _} ->
            puts_colored("timeout (may already be paused)", :yellow)
          :exit, reason ->
            puts_colored("exit: #{inspect(reason)}", :yellow)
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

  defp execute_action(:lora_raw) do
    if not LoRa.connected?() do
      puts_colored("LoRa not connected. Connect first with 'l'.", :red)
    else
      puts_colored("\nLoRa Raw Command Mode (type 'exit' to return to menu)", :cyan)
      lora_raw_loop()
    end
  end

  defp execute_action(:lora_config) do
    if not LoRa.connected?() do
      puts_colored("LoRa not connected. Connect first with 'l'.", :red)
    else
      radio_config_menu()
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

  defp lora_raw_loop do
    IO.write(Owl.Data.tag("lora> ", :yellow) |> Owl.Data.to_chardata())
    cmd = IO.gets("") |> String.trim()

    cond do
      cmd == "" ->
        lora_raw_loop()

      cmd == "exit" ->
        puts_colored("Exiting raw command mode.", :cyan)

      true ->
        case LoRa.send_command(cmd, 5_000) do
          {:ok, response} ->
            puts_colored("< #{response}", :green)
          {:error, :timeout} ->
            puts_colored("< timeout", :red)
          {:error, reason} ->
            puts_colored("< error: #{inspect(reason)}", :red)
        end
        lora_raw_loop()
    end
  rescue
    _ ->
      puts_colored("Error sending command", :red)
      lora_raw_loop()
  catch
    :exit, {:timeout, _} ->
      puts_colored("< timeout", :red)
      lora_raw_loop()
    :exit, reason ->
      puts_colored("< exit: #{inspect(reason)}", :red)
      lora_raw_loop()
  end

  # ============================================
  # Radio Config Menu
  # ============================================

  defp radio_config_menu do
    puts_colored("\n── Radio Configuration ──", :blue)

    # Show current settings
    case get_radio_settings() do
      {:ok, settings} ->
        IO.puts("\nCurrent: #{settings.frequency} Hz | SF#{settings.sf} | #{settings.bw} kHz | #{settings.power} dBm")
      {:error, _} ->
        IO.puts("\nCurrent: (unable to read)")
    end

    IO.puts("")
    puts_colored("Presets:", :cyan)
    Enum.each(@radio_presets, fn {key, name, desc, sf, bw, pwr} ->
      key_str = Owl.Data.tag("[#{key}]", :yellow) |> Owl.Data.to_chardata() |> IO.iodata_to_binary()
      IO.puts("  #{key_str} #{name} - #{desc} (SF#{sf}, #{bw}kHz, #{pwr}dBm)")
    end)

    IO.puts("")
    puts_colored("Custom:", :cyan)
    custom_key = Owl.Data.tag("[5]", :yellow) |> Owl.Data.to_chardata() |> IO.iodata_to_binary()
    back_key = Owl.Data.tag("[b]", :yellow) |> Owl.Data.to_chardata() |> IO.iodata_to_binary()
    IO.puts("  #{custom_key} Custom settings...")
    IO.puts("  #{back_key} Back to main menu")

    IO.puts("")
    IO.write(Owl.Data.tag("Select option: ", :cyan) |> Owl.Data.to_chardata())
    input = IO.gets("") |> String.trim() |> String.downcase()

    case input do
      "b" ->
        :ok

      "5" ->
        custom_radio_config()

      key ->
        case Enum.find(@radio_presets, fn {k, _, _, _, _, _} -> k == key end) do
          {_, name, _, sf, bw, pwr} ->
            apply_radio_preset(name, sf, bw, pwr)
          nil ->
            puts_colored("Invalid option.", :red)
            radio_config_menu()
        end
    end
  end

  defp apply_radio_preset(name, sf, bw, pwr) do
    puts_colored("\nApplying '#{name}' preset...", :cyan)

    with_spinner("Setting SF#{sf}...", fn -> LoRa.set_spreading_factor(sf) end)
    with_spinner("Setting #{bw}kHz bandwidth...", fn -> LoRa.set_bandwidth(bw) end)
    with_spinner("Setting #{pwr}dBm power...", fn -> LoRa.set_power(pwr) end)

    puts_colored("✓ Radio configured: SF#{sf}, #{bw}kHz, #{pwr}dBm", :green)
  end

  defp custom_radio_config do
    puts_colored("\n── Custom Radio Settings ──", :blue)
    IO.puts("Enter new values or press Enter to keep current.\n")

    # Frequency
    IO.puts("Frequency options: [1] 868.1 MHz (EU)  [2] 915 MHz (US)  [3] 923.3 MHz (US)")
    IO.write(Owl.Data.tag("Frequency [1-3]: ", :cyan) |> Owl.Data.to_chardata())
    freq_input = IO.gets("") |> String.trim()
    unless freq_input == "" do
      freq = case freq_input do
        "1" -> 868_100_000
        "2" -> 915_000_000
        "3" -> 923_300_000
        _ -> nil
      end
      if freq do
        with_spinner("Setting frequency #{freq} Hz...", fn -> LoRa.set_frequency(freq) end)
      end
    end

    # Spreading Factor
    IO.puts("\nSpreading Factor: 7 (fastest) to 12 (longest range)")
    IO.write(Owl.Data.tag("SF [7-12]: ", :cyan) |> Owl.Data.to_chardata())
    sf_input = IO.gets("") |> String.trim()
    unless sf_input == "" do
      case Integer.parse(sf_input) do
        {sf, ""} when sf in 7..12 ->
          with_spinner("Setting SF#{sf}...", fn -> LoRa.set_spreading_factor(sf) end)
        _ ->
          puts_colored("Invalid SF, skipping.", :yellow)
      end
    end

    # Bandwidth
    IO.puts("\nBandwidth options: [1] 125 kHz  [2] 250 kHz  [3] 500 kHz")
    IO.write(Owl.Data.tag("Bandwidth [1-3]: ", :cyan) |> Owl.Data.to_chardata())
    bw_input = IO.gets("") |> String.trim()
    unless bw_input == "" do
      bw = case bw_input do
        "1" -> 125
        "2" -> 250
        "3" -> 500
        _ -> nil
      end
      if bw do
        with_spinner("Setting #{bw}kHz bandwidth...", fn -> LoRa.set_bandwidth(bw) end)
      end
    end

    # Power
    IO.puts("\nTX Power: -3 to 14 dBm")
    IO.write(Owl.Data.tag("Power [-3 to 14]: ", :cyan) |> Owl.Data.to_chardata())
    pwr_input = IO.gets("") |> String.trim()
    unless pwr_input == "" do
      case Integer.parse(pwr_input) do
        {pwr, ""} when pwr in -3..14 ->
          with_spinner("Setting #{pwr}dBm power...", fn -> LoRa.set_power(pwr) end)
        _ ->
          puts_colored("Invalid power, skipping.", :yellow)
      end
    end

    puts_colored("\n✓ Custom configuration complete.", :green)
  end

  defp get_radio_settings do
    with {:ok, freq} <- LoRa.send_command("radio get freq", 2_000),
         {:ok, sf} <- LoRa.send_command("radio get sf", 2_000),
         {:ok, bw} <- LoRa.send_command("radio get bw", 2_000),
         {:ok, pwr} <- LoRa.send_command("radio get pwr", 2_000) do
      # Parse SF number from "sf7" format
      sf_num = case Regex.run(~r/sf(\d+)/, sf) do
        [_, num] -> num
        _ -> sf
      end
      {:ok, %{frequency: freq, sf: sf_num, bw: bw, power: pwr}}
    else
      error -> error
    end
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
    default = %{
      connected: false,
      echo_running: false,
      echo_rx_count: 0,
      echo_tx_count: 0,
      beacon_running: false,
      beacon_tx_count: 0,
      beacon_interval: 0
    }

    try do
      connected = LoRa.connected?()
      echo_status = safe_genserver_call(fn -> Echo.status() end, %{running: false, rx_count: 0, tx_count: 0})
      beacon_status = safe_genserver_call(fn -> Beacon.status() end, %{running: false, tx_count: 0, interval: 5000})

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
      _ -> default
    catch
      :exit, _ -> default
    end
  end

  defp safe_genserver_call(fun, default) do
    try do
      fun.()
    rescue
      _ -> default
    catch
      :exit, _ -> default
    end
  end
end
