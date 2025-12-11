defmodule D2dResponder do
  @moduledoc """
  D2D Responder - LoRa beacon and echo modes for Raspberry Pi.

  ## Usage

  Start the application and connect to the LoRa module:

      D2dResponder.connect()

  Start beacon mode (transmit periodic messages):

      D2dResponder.beacon()
      D2dResponder.beacon(message: "HELLO", interval: 3000)

  Start echo mode (receive and echo back messages):

      D2dResponder.echo()
      D2dResponder.echo(prefix: "ACK:")

  Stop modes:

      D2dResponder.stop_beacon()
      D2dResponder.stop_echo()

  Status:

      D2dResponder.status()
  """

  alias D2dResponder.{LoRa, Beacon, Echo}
  alias D2dResponder.Network

  @default_port "/dev/ttyACM0"

  @doc """
  Connect to the LoRa module on the specified port.
  """
  def connect(port \\ @default_port) do
    case LoRa.connect(port) do
      :ok ->
        # Pause MAC layer for raw radio mode
        LoRa.pause_mac()
        IO.puts("Connected to #{port}")
        :ok

      {:error, reason} ->
        IO.puts("Connection failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Disconnect from the LoRa module.
  """
  def disconnect do
    LoRa.disconnect()
    IO.puts("Disconnected")
  end

  @doc """
  Start beacon mode - transmit periodic messages.

  Options:
    - `:message` - The message to transmit (default: "BEACON")
    - `:interval` - Milliseconds between transmissions (default: 5000)
  """
  def beacon(opts \\ []) do
    case Beacon.start_beacon(opts) do
      :ok ->
        message = Keyword.get(opts, :message, "BEACON")
        interval = Keyword.get(opts, :interval, 5000)
        IO.puts("Beacon started: '#{message}' every #{interval}ms")
        :ok

      {:error, :already_running} ->
        IO.puts("Beacon already running")
        {:error, :already_running}
    end
  end

  @doc """
  Stop beacon mode.
  """
  def stop_beacon do
    Beacon.stop_beacon()
    IO.puts("Beacon stopped")
  end

  @doc """
  Start echo mode - listen for messages and echo them back.

  Options:
    - `:prefix` - Prefix to add to echoed messages (default: "ECHO:")
  """
  def echo(opts \\ []) do
    case Echo.start_echo(opts) do
      :ok ->
        prefix = Keyword.get(opts, :prefix, "ECHO:")
        IO.puts("Echo mode started with prefix '#{prefix}'")
        :ok

      {:error, :already_running} ->
        IO.puts("Echo already running")
        {:error, :already_running}
    end
  end

  @doc """
  Stop echo mode.
  """
  def stop_echo do
    Echo.stop_echo()
    IO.puts("Echo stopped")
  end

  @doc """
  Get status of all modes.
  """
  def status do
    beacon_status = Beacon.status()
    echo_status = Echo.status()
    connected = LoRa.connected?()

    IO.puts("""

    D2D Responder Status
    ====================
    LoRa Connected: #{connected}

    Beacon Mode:
      Running:  #{beacon_status.running}
      Message:  #{beacon_status.message}
      Interval: #{beacon_status.interval}ms
      TX Count: #{beacon_status.tx_count}

    Echo Mode:
      Running:  #{echo_status.running}
      Prefix:   #{echo_status.prefix}
      RX Count: #{echo_status.rx_count}
      TX Count: #{echo_status.tx_count}
    """)

    %{
      connected: connected,
      beacon: beacon_status,
      echo: echo_status
    }
  end

  @doc """
  Transmit a single message.
  """
  def tx(message) do
    case LoRa.transmit(message) do
      {:ok, _} ->
        IO.puts("TX: #{message}")
        :ok

      {:error, reason} ->
        IO.puts("TX failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Send a raw command to the LoRa module.
  """
  def cmd(command) do
    case LoRa.send_command(command) do
      {:ok, response} ->
        IO.puts("#{command} -> #{response}")
        {:ok, response}

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Configure radio settings.
  """
  def configure(opts \\ []) do
    if freq = Keyword.get(opts, :frequency) do
      LoRa.set_frequency(freq)
      IO.puts("Frequency: #{freq} Hz")
    end

    if sf = Keyword.get(opts, :sf) do
      LoRa.set_spreading_factor(sf)
      IO.puts("Spreading Factor: SF#{sf}")
    end

    if bw = Keyword.get(opts, :bw) do
      LoRa.set_bandwidth(bw)
      IO.puts("Bandwidth: #{bw} kHz")
    end

    if pwr = Keyword.get(opts, :power) do
      LoRa.set_power(pwr)
      IO.puts("Power: #{pwr} dBm")
    end

    :ok
  end

  @doc """
  Start network services for field testing.
  Sets up WiFi ad-hoc, Bluetooth NAP, and iperf3 server.

  ## Usage
      D2dResponder.start_network()
  """
  def start_network do
    IO.puts("Starting network services...")

    IO.puts("  Starting WiFi ad-hoc...")
    case Network.WiFi.setup() do
      :ok -> IO.puts("    WiFi OK")
      {:error, e} -> IO.puts("    WiFi failed: #{inspect(e)}")
    end

    IO.puts("  Starting Bluetooth NAP...")
    case Network.Bluetooth.start_server() do
      :ok -> IO.puts("    Bluetooth OK")
      {:error, e} -> IO.puts("    Bluetooth failed: #{inspect(e)}")
    end

    IO.puts("  iperf3 server should already be running")
    IO.puts("Done!")
    :ok
  end

  @doc """
  Reset all network services to normal state (WiFi + Bluetooth).
  Use this instead of rebooting the Pi.

  ## Usage
      D2dResponder.reset_network()
  """
  def reset_network do
    IO.puts("Resetting network services...")

    IO.puts("  Resetting WiFi...")
    Network.WiFi.reset()

    IO.puts("  Resetting Bluetooth...")
    Network.Bluetooth.reset()

    IO.puts("Done! Network services restored to normal state.")
    :ok
  end

  @doc """
  Get network status.
  """
  def network_status do
    wifi = Network.WiFi.get_status()
    bt = Network.Bluetooth.get_status()
    iperf = Network.Responder.get_status()

    IO.puts("""

    Network Status
    ==============
    WiFi:
      Connected: #{wifi.connected}
      Interface: #{wifi.interface}
      IP: #{wifi.ip}

    Bluetooth:
      Connected: #{bt.connected}
      Mode: #{bt.mode}
      IP: #{bt.ip}

    iperf3 Server:
      Running: #{iperf.running}
      Port: #{iperf.port || "N/A"}
    """)

    %{wifi: wifi, bluetooth: bt, iperf: iperf}
  end
end
