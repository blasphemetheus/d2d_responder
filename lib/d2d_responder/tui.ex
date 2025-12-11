defmodule D2dResponder.TUI do
  @moduledoc """
  Terminal UI for D2D Responder using Owl.
  Run with: D2dResponder.TUI.run()
  """

  alias D2dResponder.Network.{WiFi, Bluetooth, Responder}

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
    {"s", "Show Status", :status},
    {"q", "Quit", :quit}
  ]

  def run do
    IO.puts(Owl.Data.tag("\n═══ D2D Responder Control Panel ═══\n", :cyan))
    loop()
  end

  defp loop do
    print_status()
    print_menu()

    case get_input() do
      :quit ->
        IO.puts(Owl.Data.tag("\nGoodbye!\n", :yellow))
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

    IO.puts(Owl.Data.tag("── Status ──", :blue))

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
    IO.puts(Owl.Data.tag("── Actions ──", :blue))

    Enum.each(@menu_items, fn {key, label, _action} ->
      key_str = Owl.Data.tag("[#{key}]", :yellow) |> Owl.Data.to_chardata() |> IO.iodata_to_binary()
      IO.puts("  #{key_str} #{label}")
    end)

    IO.puts("")
  end

  defp get_input do
    input =
      Owl.IO.input(label: Owl.Data.tag("Select option: ", :cyan))
      |> String.trim()
      |> String.downcase()

    case Enum.find(@menu_items, fn {key, _, _} -> key == input end) do
      {_, _, action} -> action
      nil ->
        IO.puts(Owl.Data.tag("Invalid option, try again.", :red))
        get_input()
    end
  end

  defp execute_action(:start_all) do
    IO.puts(Owl.Data.tag("\nStarting all network services...", :cyan))

    with_spinner("Starting WiFi ad-hoc...", fn -> WiFi.setup() end)
    with_spinner("Starting Bluetooth NAP...", fn -> Bluetooth.start_server() end)
    with_spinner("Starting iperf3...", fn -> Responder.start_iperf_server() end)

    IO.puts(Owl.Data.tag("✓ All services started!", :green))
  end

  defp execute_action(:stop_all) do
    IO.puts(Owl.Data.tag("\nStopping all network services...", :cyan))

    with_spinner("Stopping WiFi...", fn -> WiFi.teardown() end)
    with_spinner("Stopping Bluetooth...", fn -> Bluetooth.stop_server() end)
    with_spinner("Stopping iperf3...", fn -> Responder.stop_iperf_server() end)

    IO.puts(Owl.Data.tag("✓ All services stopped!", :green))
  end

  defp execute_action(:reset_all) do
    IO.puts(Owl.Data.tag("\nResetting all network services...", :cyan))

    with_spinner("Resetting WiFi...", fn -> WiFi.reset() end)
    with_spinner("Resetting Bluetooth...", fn -> Bluetooth.reset() end)
    with_spinner("Restarting iperf3...", fn ->
      Responder.stop_iperf_server()
      Responder.start_iperf_server()
    end)

    IO.puts(Owl.Data.tag("✓ All services reset!", :green))
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

  defp execute_action(:status) do
    IO.puts(Owl.Data.tag("\n── Detailed Status ──", :blue))

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

    task = Task.async(fn -> func.() end)
    spinner_loop(task)

    case Task.await(task, 60_000) do
      :ok ->
        IO.puts(Owl.Data.tag("✓", :green))
        :ok
      {:ok, _} ->
        IO.puts(Owl.Data.tag("✓", :green))
        :ok
      {:error, reason} ->
        IO.puts(Owl.Data.tag("✗ #{inspect(reason)}", :red))
        {:error, reason}
      other ->
        IO.puts(Owl.Data.tag("✓", :green))
        other
    end
  rescue
    e ->
      IO.puts(Owl.Data.tag("✗ #{inspect(e)}", :red))
      {:error, e}
  end

  defp spinner_loop(task) do
    frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    spinner_loop(task, frames, 0)
  end

  defp spinner_loop(task, frames, index) do
    case Task.yield(task, 100) do
      nil ->
        frame = Enum.at(frames, rem(index, length(frames)))
        IO.write("\b#{frame}")
        spinner_loop(task, frames, index + 1)
      _ ->
        IO.write("\b")
    end
  end

  defp print_result(:ok, service), do: IO.puts(Owl.Data.tag("#{service} operation completed.", :green))
  defp print_result({:ok, _}, service), do: IO.puts(Owl.Data.tag("#{service} operation completed.", :green))
  defp print_result({:error, reason}, service), do: IO.puts(Owl.Data.tag("#{service} failed: #{inspect(reason)}", :red))
  defp print_result(_, service), do: IO.puts(Owl.Data.tag("#{service} operation completed.", :green))

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
end
