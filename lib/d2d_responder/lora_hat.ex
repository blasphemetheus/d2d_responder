defmodule D2dResponder.LoRaHAT do
  @moduledoc """
  Wrapper for Dragino LoRa/GPS HAT (SX1276) that provides a similar API
  to the RN2903 UART module, making it interchangeable in the TUI.

  ## Dragino LoRa/GPS HAT Pinout (v1.3+)

  | Function | Physical Pin | BCM Pin | Notes                    |
  |----------|-------------|---------|--------------------------|
  | MOSI     | 19          | 10      | SPI0 MOSI               |
  | MISO     | 21          | 9       | SPI0 MISO               |
  | SCLK     | 23          | 11      | SPI0 SCLK               |
  | NSS/CS   | 22          | 25      | Directly connected      |
  | RESET    | 11          | 17      | Some versions use 25    |
  | DIO0     | 7           | 4       | RX/TX done interrupt    |
  | DIO1     | 16          | 23      | Optional (manual wire)  |
  | DIO2     | 18          | 24      | Optional (manual wire)  |

  ## SPI Note

  The Dragino HAT uses GPIO 25 as chip select instead of the standard
  CE0/CE1. You may need to configure a device tree overlay, or use
  spidev0.0 with GPIO-controlled CS.

  ## Usage

      # Start the module
      {:ok, _pid} = D2dResponder.LoRaHAT.start_link()

      # Connect (initialize the radio)
      :ok = D2dResponder.LoRaHAT.connect()

      # Same API as LoRa module
      D2dResponder.LoRaHAT.transmit("Hello")
      D2dResponder.LoRaHAT.receive_mode(0)
  """
  use GenServer
  require Logger

  alias D2dResponder.SX1276

  # Dragino HAT default pinout
  @default_config %{
    spi_bus: "spidev0.0",
    spi_speed: 8_000_000,
    reset_pin: 17,       # Some boards use 25
    dio0_pin: 4,
    frequency: 915_000_000,  # US frequency
    spreading_factor: 7,
    bandwidth: 125000,
    coding_rate: 5,
    tx_power: 14
  }

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Connect/initialize the LoRa HAT. Similar to RN2903 connect().
  """
  def connect(opts \\ []) do
    GenServer.call(__MODULE__, {:connect, opts}, 10_000)
  end

  def disconnect do
    GenServer.call(__MODULE__, :disconnect)
  end

  @doc """
  Transmit data - same API as RN2903 module.
  """
  def transmit(data) when is_binary(data) do
    GenServer.call(__MODULE__, {:transmit, data}, 10_000)
  end

  @doc """
  Enter receive mode. 0 = continuous, >0 = timeout in ms.
  """
  def receive_mode(timeout_ms \\ 0) do
    GenServer.call(__MODULE__, {:receive_mode, timeout_ms})
  end

  def connected? do
    GenServer.call(__MODULE__, :connected?)
  end

  def subscribe(pid) do
    GenServer.call(__MODULE__, {:subscribe, pid})
  end

  def unsubscribe(pid) do
    GenServer.call(__MODULE__, {:unsubscribe, pid})
  end

  # Radio settings - same API as RN2903

  def set_spreading_factor(sf) when sf in 7..12 do
    GenServer.call(__MODULE__, {:set_spreading_factor, sf})
  end

  def set_bandwidth(bw) when bw in [125, 250, 500] do
    # Convert from kHz to Hz for SX1276
    GenServer.call(__MODULE__, {:set_bandwidth, bw * 1000})
  end

  def set_power(pwr) when pwr in 2..20 do
    GenServer.call(__MODULE__, {:set_tx_power, pwr})
  end

  def set_frequency(freq) do
    GenServer.call(__MODULE__, {:set_frequency, freq})
  end

  def get_radio_settings do
    GenServer.call(__MODULE__, :get_radio_settings)
  end

  @doc """
  Pause MAC - not needed for SX1276 (no LoRaWAN stack), but provided for compatibility.
  """
  def pause_mac do
    {:ok, "4294967295"}  # Same response as RN2903
  end

  # Server callbacks

  @impl true
  def init(opts) do
    config = Map.merge(@default_config, Map.new(opts))

    state = %{
      config: config,
      connected: false,
      subscribers: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:connect, opts}, _from, state) do
    config = Map.merge(state.config, Map.new(opts))

    # Start the SX1276 driver if not already started
    case ensure_sx1276_started(config) do
      :ok ->
        case SX1276.begin(config.frequency) do
          :ok ->
            # Apply saved settings
            SX1276.set_spreading_factor(config.spreading_factor)
            SX1276.set_bandwidth(config.bandwidth)
            SX1276.set_coding_rate(config.coding_rate)
            SX1276.set_tx_power(config.tx_power)

            Logger.info("LoRaHAT: Connected - #{config.frequency / 1_000_000} MHz, SF#{config.spreading_factor}")
            {:reply, :ok, %{state | connected: true, config: config}}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:disconnect, _from, state) do
    if state.connected do
      SX1276.sleep()
    end
    {:reply, :ok, %{state | connected: false}}
  end

  @impl true
  def handle_call({:transmit, data}, _from, %{connected: true} = state) do
    D2dResponder.FileLogger.log_tx(data, Base.encode16(data))

    case SX1276.transmit(data) do
      :ok ->
        D2dResponder.FileLogger.log_event(:tx_ok)
        notify_subscribers(state.subscribers, :lora_tx_ok)
        {:reply, {:ok, "radio_tx_ok"}, state}

      {:error, reason} ->
        D2dResponder.FileLogger.log_event(:tx_error)
        notify_subscribers(state.subscribers, :lora_tx_error)
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:receive_mode, timeout_ms}, _from, %{connected: true} = state) do
    # Subscribe this GenServer to SX1276 RX events
    SX1276.subscribe(self())
    result = SX1276.receive_mode(timeout_ms)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:connected?, _from, state) do
    {:reply, state.connected, state}
  end

  @impl true
  def handle_call({:subscribe, pid}, _from, state) do
    if pid in state.subscribers do
      {:reply, :ok, state}
    else
      {:reply, :ok, %{state | subscribers: [pid | state.subscribers]}}
    end
  end

  @impl true
  def handle_call({:unsubscribe, pid}, _from, state) do
    {:reply, :ok, %{state | subscribers: List.delete(state.subscribers, pid)}}
  end

  @impl true
  def handle_call({:set_spreading_factor, sf}, _from, %{connected: true} = state) do
    SX1276.set_spreading_factor(sf)
    {:reply, {:ok, "ok"}, update_in(state.config, &Map.put(&1, :spreading_factor, sf))}
  end

  @impl true
  def handle_call({:set_bandwidth, bw}, _from, %{connected: true} = state) do
    SX1276.set_bandwidth(bw)
    {:reply, {:ok, "ok"}, update_in(state.config, &Map.put(&1, :bandwidth, bw))}
  end

  @impl true
  def handle_call({:set_tx_power, pwr}, _from, %{connected: true} = state) do
    SX1276.set_tx_power(pwr)
    {:reply, {:ok, "ok"}, update_in(state.config, &Map.put(&1, :tx_power, pwr))}
  end

  @impl true
  def handle_call({:set_frequency, freq}, _from, %{connected: true} = state) do
    SX1276.set_frequency(freq)
    {:reply, {:ok, "ok"}, update_in(state.config, &Map.put(&1, :frequency, freq))}
  end

  @impl true
  def handle_call(:get_radio_settings, _from, %{connected: true} = state) do
    config = SX1276.get_config()
    {:reply, {:ok, config}, state}
  end

  @impl true
  def handle_call(_, _from, %{connected: false} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  # Forward RX events from SX1276 to our subscribers
  @impl true
  def handle_info({:lora_rx, data, hex, opts}, state) do
    rssi = Keyword.get(opts, :rssi, 0)
    snr = Keyword.get(opts, :snr, 0)

    Logger.debug("LoRaHAT: RX #{byte_size(data)} bytes, RSSI=#{rssi}, SNR=#{snr}")

    # Forward to subscribers with same format as RN2903
    for pid <- state.subscribers do
      send(pid, {:lora_rx, data, hex})
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:lora_tx_ok, state) do
    notify_subscribers(state.subscribers, :lora_tx_ok)
    {:noreply, state}
  end

  @impl true
  def handle_info(:lora_tx_error, state) do
    notify_subscribers(state.subscribers, :lora_tx_error)
    {:noreply, state}
  end

  # Private

  defp ensure_sx1276_started(config) do
    case Process.whereis(SX1276) do
      nil ->
        case SX1276.start_link(
          spi_bus: config.spi_bus,
          spi_speed: config.spi_speed,
          reset_pin: config.reset_pin,
          dio0_pin: config.dio0_pin
        ) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          error -> error
        end

      _pid ->
        :ok
    end
  end

  defp notify_subscribers(subscribers, message) do
    for pid <- subscribers, do: send(pid, message)
  end
end
