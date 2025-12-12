defmodule D2dResponder.SX1276 do
  @moduledoc """
  Low-level driver for SX1276 LoRa transceiver via SPI.

  This handles direct register access for the Semtech SX1276/77/78/79 chips
  used in modules like the Dragino LoRa/GPS HAT.

  Reference: SX1276/77/78/79 Datasheet, Semtech
  """
  use GenServer
  import Bitwise
  require Logger

  # SX1276 Register addresses
  @reg_fifo              0x00
  @reg_op_mode           0x01
  @reg_frf_msb           0x06
  @reg_frf_mid           0x07
  @reg_frf_lsb           0x08
  @reg_pa_config         0x09
  @reg_ocp               0x0B
  @reg_lna               0x0C
  @reg_fifo_addr_ptr     0x0D
  @reg_fifo_tx_base_addr 0x0E
  @reg_fifo_rx_base_addr 0x0F
  @reg_fifo_rx_current   0x10
  @reg_irq_flags_mask    0x11
  @reg_irq_flags         0x12
  @reg_rx_nb_bytes       0x13
  @reg_pkt_snr_value     0x19
  @reg_pkt_rssi_value    0x1A
  @reg_modem_config_1    0x1D
  @reg_modem_config_2    0x1E
  @reg_symb_timeout_lsb  0x1F
  @reg_preamble_msb      0x20
  @reg_preamble_lsb      0x21
  @reg_payload_length    0x22
  @reg_modem_config_3    0x26
  @reg_freq_error_msb    0x28
  @reg_freq_error_mid    0x29
  @reg_freq_error_lsb    0x2A
  @reg_rssi_wideband     0x2C
  @reg_detection_opt     0x31
  @reg_detection_thresh  0x37
  @reg_sync_word         0x39
  @reg_dio_mapping_1     0x40
  @reg_version           0x42
  @reg_pa_dac            0x4D

  # Operating modes
  @mode_sleep            0x00
  @mode_stdby            0x01
  @mode_tx               0x03
  @mode_rx_continuous    0x05
  @mode_rx_single        0x06
  @mode_lora             0x80

  # IRQ flags
  @irq_rx_done           0x40
  @irq_payload_crc_error 0x20
  @irq_tx_done           0x08

  # PA config
  @pa_boost              0x80

  # Frequency settings for 915 MHz (US)
  @fxosc                 32_000_000
  @fstep                 @fxosc / 524_288  # 2^19

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Initialize the SX1276 for LoRa mode at specified frequency.
  Frequency in Hz (e.g., 915_000_000 for 915 MHz).
  """
  def begin(frequency \\ 915_000_000) do
    GenServer.call(__MODULE__, {:begin, frequency})
  end

  def set_frequency(freq_hz) do
    GenServer.call(__MODULE__, {:set_frequency, freq_hz})
  end

  def set_spreading_factor(sf) when sf in 6..12 do
    GenServer.call(__MODULE__, {:set_spreading_factor, sf})
  end

  def set_bandwidth(bw) when bw in [7800, 10400, 15600, 20800, 31250, 41700, 62500, 125000, 250000, 500000] do
    GenServer.call(__MODULE__, {:set_bandwidth, bw})
  end

  def set_coding_rate(cr) when cr in 5..8 do
    GenServer.call(__MODULE__, {:set_coding_rate, cr})
  end

  def set_tx_power(level) when level in 2..20 do
    GenServer.call(__MODULE__, {:set_tx_power, level})
  end

  def set_sync_word(sw) do
    GenServer.call(__MODULE__, {:set_sync_word, sw})
  end

  @doc """
  Transmit data. Returns :ok when TX complete, or {:error, reason}.
  """
  def transmit(data) when is_binary(data) do
    GenServer.call(__MODULE__, {:transmit, data}, 10_000)
  end

  @doc """
  Enter receive mode. Messages received will be sent to subscribers.
  timeout_ms: 0 for continuous, >0 for single receive with timeout
  """
  def receive_mode(timeout_ms \\ 0) do
    GenServer.call(__MODULE__, {:receive_mode, timeout_ms})
  end

  def standby do
    GenServer.call(__MODULE__, :standby)
  end

  def sleep do
    GenServer.call(__MODULE__, :sleep)
  end

  @doc """
  Disconnect and release all GPIO/SPI resources.
  """
  def disconnect do
    GenServer.call(__MODULE__, :disconnect)
  end

  @doc """
  Hardware reset via GPIO reset pin. Toggles low then high.
  """
  def hardware_reset do
    GenServer.call(__MODULE__, :hardware_reset)
  end

  def get_rssi do
    GenServer.call(__MODULE__, :get_rssi)
  end

  def get_version do
    GenServer.call(__MODULE__, :get_version)
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

  def get_config do
    GenServer.call(__MODULE__, :get_config)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    spi_bus = Keyword.get(opts, :spi_bus, "spidev0.0")
    spi_speed = Keyword.get(opts, :spi_speed, 8_000_000)
    reset_pin = Keyword.get(opts, :reset_pin, 17)
    dio0_pin = Keyword.get(opts, :dio0_pin, 4)
    # Dragino HAT uses GPIO25 for CS instead of standard CE0/CE1
    cs_pin = Keyword.get(opts, :cs_pin, 25)

    state = %{
      spi: nil,
      spi_bus: spi_bus,
      spi_speed: spi_speed,
      reset_pin: reset_pin,
      reset_gpio: nil,
      cs_pin: cs_pin,
      cs_gpio: nil,
      dio0_pin: dio0_pin,
      dio0_gpio: nil,
      connected: false,
      frequency: 915_000_000,
      spreading_factor: 7,
      bandwidth: 125000,
      coding_rate: 5,
      tx_power: 14,
      subscribers: [],
      rx_mode: false
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:begin, frequency}, _from, state) do
    case do_begin(frequency, state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:set_frequency, freq_hz}, _from, %{connected: true} = state) do
    do_set_frequency(freq_hz, state)
    {:reply, :ok, %{state | frequency: freq_hz}}
  end

  @impl true
  def handle_call({:set_spreading_factor, sf}, _from, %{connected: true} = state) do
    do_set_spreading_factor(sf, state)
    {:reply, :ok, %{state | spreading_factor: sf}}
  end

  @impl true
  def handle_call({:set_bandwidth, bw}, _from, %{connected: true} = state) do
    do_set_bandwidth(bw, state)
    {:reply, :ok, %{state | bandwidth: bw}}
  end

  @impl true
  def handle_call({:set_coding_rate, cr}, _from, %{connected: true} = state) do
    do_set_coding_rate(cr, state)
    {:reply, :ok, %{state | coding_rate: cr}}
  end

  @impl true
  def handle_call({:set_tx_power, level}, _from, %{connected: true} = state) do
    do_set_tx_power(level, state)
    {:reply, :ok, %{state | tx_power: level}}
  end

  @impl true
  def handle_call({:set_sync_word, sw}, _from, %{connected: true} = state) do
    write_register(@reg_sync_word, sw, state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:transmit, data}, _from, %{connected: true} = state) do
    result = do_transmit(data, state)
    {:reply, result, %{state | rx_mode: false}}
  end

  @impl true
  def handle_call({:receive_mode, timeout_ms}, _from, %{connected: true} = state) do
    Logger.debug("SX1276: Entering RX mode (timeout=#{timeout_ms}ms)")
    do_receive_mode(timeout_ms, state)
    {:reply, :ok, %{state | rx_mode: true}}
  end

  @impl true
  def handle_call(:standby, _from, %{connected: true} = state) do
    set_mode(@mode_lora ||| @mode_stdby, state)
    {:reply, :ok, %{state | rx_mode: false}}
  end

  @impl true
  def handle_call(:sleep, _from, %{connected: true} = state) do
    set_mode(@mode_lora ||| @mode_sleep, state)
    {:reply, :ok, %{state | rx_mode: false}}
  end

  @impl true
  def handle_call(:disconnect, _from, state) do
    Logger.info("SX1276: Disconnecting and releasing resources")
    # Close all handles
    if state.reset_gpio, do: Circuits.GPIO.close(state.reset_gpio)
    if state.cs_gpio, do: Circuits.GPIO.close(state.cs_gpio)
    if state.dio0_gpio, do: Circuits.GPIO.close(state.dio0_gpio)
    if state.spi, do: Circuits.SPI.close(state.spi)
    {:reply, :ok, %{state |
      connected: false,
      rx_mode: false,
      spi: nil,
      reset_gpio: nil,
      cs_gpio: nil,
      dio0_gpio: nil
    }}
  end

  @impl true
  def handle_call(:hardware_reset, _from, %{reset_gpio: gpio} = state) when not is_nil(gpio) do
    Logger.info("SX1276: Hardware reset via GPIO")
    # Toggle reset pin: low -> wait -> high -> wait
    Circuits.GPIO.write(gpio, 0)
    Process.sleep(10)
    Circuits.GPIO.write(gpio, 1)
    Process.sleep(10)
    {:reply, :ok, %{state | connected: false, rx_mode: false}}
  end

  @impl true
  def handle_call(:hardware_reset, _from, state) do
    {:reply, {:error, :no_reset_gpio}, state}
  end

  @impl true
  def handle_call(:get_rssi, _from, %{connected: true} = state) do
    rssi = read_register(@reg_pkt_rssi_value, state) - 157
    {:reply, rssi, state}
  end

  @impl true
  def handle_call(:get_version, _from, %{connected: true} = state) do
    version = read_register(@reg_version, state)
    {:reply, {:ok, version}, state}
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
  def handle_call(:get_config, _from, state) do
    config = %{
      frequency: state.frequency,
      spreading_factor: state.spreading_factor,
      bandwidth: state.bandwidth,
      coding_rate: state.coding_rate,
      tx_power: state.tx_power,
      connected: state.connected
    }
    {:reply, config, state}
  end

  @impl true
  def handle_call(_, _from, %{connected: false} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  # DIO0 interrupt handler (RX done or TX done)
  @impl true
  def handle_info({:circuits_gpio, pin, _timestamp, 1}, state) do
    Logger.debug("SX1276: DIO0 interrupt (pin #{pin}), rx_mode=#{state.rx_mode}")
    handle_dio0_interrupt(state)
  end

  @impl true
  def handle_info({:circuits_gpio, _pin, _timestamp, 0}, state) do
    {:noreply, state}
  end

  # Private functions

  defp do_begin(frequency, state) do
    Logger.info("SX1276: Initializing on #{state.spi_bus}, reset=GPIO#{state.reset_pin}, CS=GPIO#{state.cs_pin}, DIO0=GPIO#{state.dio0_pin}")

    # Open resources one at a time with cleanup on failure
    with {:ok, spi} <- open_spi(state),
         {:ok, reset_gpio} <- open_gpio(state.reset_pin, :output, [spi]),
         {:ok, cs_gpio} <- open_gpio(state.cs_pin, :output, [spi, reset_gpio]),
         {:ok, dio0_gpio} <- open_gpio(state.dio0_pin, :input, [spi, reset_gpio, cs_gpio]) do

      # CS starts high (deselected)
      Circuits.GPIO.write(cs_gpio, 1)

      state = %{state | spi: spi, reset_gpio: reset_gpio, cs_gpio: cs_gpio, dio0_gpio: dio0_gpio}

      # Hardware reset
      Circuits.GPIO.write(reset_gpio, 0)
      Process.sleep(10)
      Circuits.GPIO.write(reset_gpio, 1)
      Process.sleep(10)

      # Verify chip version
      version = read_register(@reg_version, state)
      Logger.info("SX1276: Chip version = 0x#{Integer.to_string(version, 16)}")

      if version != 0x12 do
        Logger.error("SX1276: Invalid version 0x#{Integer.to_string(version, 16)}, expected 0x12")
        # Clean up on failure
        Circuits.GPIO.close(reset_gpio)
        Circuits.GPIO.close(cs_gpio)
        Circuits.GPIO.close(dio0_gpio)
        Circuits.SPI.close(spi)
        {:error, :invalid_chip}
      else
        # Set up DIO0 interrupt
        Circuits.GPIO.set_interrupts(dio0_gpio, :rising)

        # Initialize for LoRa mode
        set_mode(@mode_lora ||| @mode_sleep, state)
        Process.sleep(10)

        # Set frequency
        do_set_frequency(frequency, state)

        # Set FIFO base addresses
        write_register(@reg_fifo_tx_base_addr, 0x00, state)
        write_register(@reg_fifo_rx_base_addr, 0x00, state)

        # Set LNA boost
        write_register(@reg_lna, read_register(@reg_lna, state) ||| 0x03, state)

        # Set auto AGC
        write_register(@reg_modem_config_3, 0x04, state)

        # Set TX power (default 14 dBm with PA_BOOST)
        do_set_tx_power(14, state)

        # Set spreading factor (default SF7)
        do_set_spreading_factor(7, state)

        # Set bandwidth (default 125kHz)
        do_set_bandwidth(125000, state)

        # Set coding rate (default 4/5)
        do_set_coding_rate(5, state)

        # Enable CRC (bit 2 of modem_config_2) - required to match RN2903
        config2 = read_register(@reg_modem_config_2, state)
        write_register(@reg_modem_config_2, config2 ||| 0x04, state)

        # Ensure explicit header mode (bit 0 of modem_config_1 = 0) - matches RN2903
        config1 = read_register(@reg_modem_config_1, state)
        write_register(@reg_modem_config_1, config1 &&& 0xFE, state)

        # Set preamble length (default 8)
        write_register(@reg_preamble_msb, 0x00, state)
        write_register(@reg_preamble_lsb, 0x08, state)

        # Set sync word (0x12 for private networks, 0x34 for LoRaWAN)
        # Sync word 0x34 matches RN2903 default (0x12 is private, 0x34 is LoRaWAN public)
        write_register(@reg_sync_word, 0x34, state)

        # Go to standby
        set_mode(@mode_lora ||| @mode_stdby, state)

        # Log modem config for debugging
        mc1 = read_register(@reg_modem_config_1, state)
        mc2 = read_register(@reg_modem_config_2, state)
        mc3 = read_register(@reg_modem_config_3, state)
        sw = read_register(@reg_sync_word, state)
        Logger.info("SX1276: ModemConfig1=0x#{Integer.to_string(mc1, 16)}, ModemConfig2=0x#{Integer.to_string(mc2, 16)}, ModemConfig3=0x#{Integer.to_string(mc3, 16)}, SyncWord=0x#{Integer.to_string(sw, 16)}")
        Logger.info("SX1276: CRC=#{if (mc2 &&& 0x04) != 0, do: "ON", else: "OFF"}, Header=#{if (mc1 &&& 0x01) != 0, do: "Implicit", else: "Explicit"}")

        Logger.info("SX1276: Initialized at #{frequency / 1_000_000} MHz")
        {:ok, %{state | connected: true, frequency: frequency}}
      end
    else
      {:error, reason} ->
        Logger.error("SX1276: Failed to initialize: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp do_set_frequency(freq_hz, state) do
    frf = trunc(freq_hz / @fstep)
    write_register(@reg_frf_msb, (frf >>> 16) &&& 0xFF, state)
    write_register(@reg_frf_mid, (frf >>> 8) &&& 0xFF, state)
    write_register(@reg_frf_lsb, frf &&& 0xFF, state)
  end

  defp do_set_spreading_factor(sf, state) do
    # Detection optimize and threshold for SF6
    if sf == 6 do
      write_register(@reg_detection_opt, 0xC5, state)
      write_register(@reg_detection_thresh, 0x0C, state)
    else
      write_register(@reg_detection_opt, 0xC3, state)
      write_register(@reg_detection_thresh, 0x0A, state)
    end

    config2 = read_register(@reg_modem_config_2, state)
    write_register(@reg_modem_config_2, (config2 &&& 0x0F) ||| ((sf <<< 4) &&& 0xF0), state)
  end

  defp do_set_bandwidth(bw, state) do
    bw_bits = case bw do
      7800    -> 0x00
      10400   -> 0x10
      15600   -> 0x20
      20800   -> 0x30
      31250   -> 0x40
      41700   -> 0x50
      62500   -> 0x60
      125000  -> 0x70
      250000  -> 0x80
      500000  -> 0x90
    end

    config1 = read_register(@reg_modem_config_1, state)
    write_register(@reg_modem_config_1, (config1 &&& 0x0F) ||| bw_bits, state)
  end

  defp do_set_coding_rate(cr, state) do
    # cr: 5 = 4/5, 6 = 4/6, 7 = 4/7, 8 = 4/8
    cr_bits = (cr - 4) <<< 1
    config1 = read_register(@reg_modem_config_1, state)
    write_register(@reg_modem_config_1, (config1 &&& 0xF1) ||| cr_bits, state)
  end

  defp do_set_tx_power(level, state) do
    level = max(2, min(20, level))

    if level > 17 do
      # Enable +20dBm on PA_BOOST
      write_register(@reg_pa_dac, 0x87, state)
      write_register(@reg_ocp, 0x3F, state)  # OCP 240mA
      write_register(@reg_pa_config, @pa_boost ||| (level - 5), state)
    else
      write_register(@reg_pa_dac, 0x84, state)
      write_register(@reg_ocp, 0x2B, state)  # OCP 100mA
      write_register(@reg_pa_config, @pa_boost ||| (level - 2), state)
    end
  end

  defp do_transmit(data, state) do
    # Go to standby
    set_mode(@mode_lora ||| @mode_stdby, state)

    # Reset FIFO pointer
    write_register(@reg_fifo_addr_ptr, 0x00, state)

    # Write payload to FIFO
    size = byte_size(data)
    for <<byte <- data>> do
      write_register(@reg_fifo, byte, state)
    end

    # Set payload length
    write_register(@reg_payload_length, size, state)

    # Clear IRQ flags
    write_register(@reg_irq_flags, 0xFF, state)

    # Start TX
    set_mode(@mode_lora ||| @mode_tx, state)

    # Wait for TX done (poll IRQ flags, DIO0 interrupt is async)
    wait_for_tx_done(state, 5000)
  end

  defp wait_for_tx_done(state, timeout) when timeout > 0 do
    irq = read_register(@reg_irq_flags, state)
    if (irq &&& @irq_tx_done) != 0 do
      # Clear flag
      write_register(@reg_irq_flags, @irq_tx_done, state)
      set_mode(@mode_lora ||| @mode_stdby, state)
      :ok
    else
      Process.sleep(10)
      wait_for_tx_done(state, timeout - 10)
    end
  end

  defp wait_for_tx_done(_state, _timeout) do
    {:error, :tx_timeout}
  end

  defp do_receive_mode(0, state) do
    # Continuous receive
    set_mode(@mode_lora ||| @mode_stdby, state)

    # Reset FIFO pointer
    write_register(@reg_fifo_addr_ptr, 0x00, state)

    # Clear IRQ flags
    write_register(@reg_irq_flags, 0xFF, state)

    # Map DIO0 to RxDone
    write_register(@reg_dio_mapping_1, 0x00, state)

    # Start continuous RX
    set_mode(@mode_lora ||| @mode_rx_continuous, state)
  end

  defp do_receive_mode(_timeout_ms, state) do
    # Single receive mode (uses symbol timeout from register)
    set_mode(@mode_lora ||| @mode_stdby, state)
    write_register(@reg_fifo_addr_ptr, 0x00, state)
    write_register(@reg_irq_flags, 0xFF, state)
    write_register(@reg_dio_mapping_1, 0x00, state)
    set_mode(@mode_lora ||| @mode_rx_single, state)
  end

  defp handle_dio0_interrupt(%{rx_mode: true} = state) do
    irq = read_register(@reg_irq_flags, state)
    Logger.debug("SX1276: RX interrupt, IRQ flags=0x#{Integer.to_string(irq, 16)}")

    if (irq &&& @irq_rx_done) != 0 do
      # Check CRC
      if (irq &&& @irq_payload_crc_error) != 0 do
        Logger.warning("SX1276: RX CRC error")
        write_register(@reg_irq_flags, @irq_payload_crc_error, state)
      else
        # Read packet
        current_addr = read_register(@reg_fifo_rx_current, state)
        length = read_register(@reg_rx_nb_bytes, state)

        write_register(@reg_fifo_addr_ptr, current_addr, state)

        data = for _ <- 1..length, into: <<>> do
          <<read_register(@reg_fifo, state)>>
        end

        # Get signal quality
        rssi = read_register(@reg_pkt_rssi_value, state) - 157
        snr = read_register(@reg_pkt_snr_value, state)
        snr = if snr > 127, do: (snr - 256) / 4, else: snr / 4

        # Notify subscribers
        hex = Base.encode16(data)
        D2dResponder.FileLogger.log_rx(data, hex)
        for pid <- state.subscribers do
          send(pid, {:lora_rx, data, hex, rssi: rssi, snr: snr})
        end
      end

      # Clear RX done flag
      write_register(@reg_irq_flags, @irq_rx_done, state)
    end

    {:noreply, state}
  end

  defp handle_dio0_interrupt(state) do
    # TX done interrupt or spurious
    irq = read_register(@reg_irq_flags, state)
    Logger.debug("SX1276: TX/other interrupt, IRQ flags=0x#{Integer.to_string(irq, 16)}, rx_mode=#{state.rx_mode}")
    if (irq &&& @irq_tx_done) != 0 do
      write_register(@reg_irq_flags, @irq_tx_done, state)
      for pid <- state.subscribers, do: send(pid, :lora_tx_ok)
    end
    {:noreply, state}
  end

  defp set_mode(mode, state) do
    write_register(@reg_op_mode, mode, state)
  end

  defp read_register(addr, state) do
    # Toggle CS for Dragino HAT (GPIO25)
    if state.cs_gpio do
      Circuits.GPIO.write(state.cs_gpio, 0)
    end
    {:ok, <<_sent, value>>} = Circuits.SPI.transfer(state.spi, <<addr &&& 0x7F, 0x00>>)
    if state.cs_gpio do
      Circuits.GPIO.write(state.cs_gpio, 1)
    end
    value
  end

  defp write_register(addr, value, state) do
    # Toggle CS for Dragino HAT (GPIO25)
    if state.cs_gpio do
      Circuits.GPIO.write(state.cs_gpio, 0)
    end
    Circuits.SPI.transfer(state.spi, <<(addr ||| 0x80), value>>)
    if state.cs_gpio do
      Circuits.GPIO.write(state.cs_gpio, 1)
    end
  end

  # Helper to open SPI with error handling
  defp open_spi(state) do
    case Circuits.SPI.open(state.spi_bus, speed_hz: state.spi_speed, mode: 0) do
      {:ok, spi} -> {:ok, spi}
      {:error, reason} ->
        Logger.error("SX1276: Failed to open SPI #{state.spi_bus}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Helper to open GPIO with cleanup of previously opened resources on failure
  defp open_gpio(pin, direction, cleanup_on_fail) do
    case Circuits.GPIO.open(pin, direction) do
      {:ok, gpio} -> {:ok, gpio}
      {:error, reason} ->
        Logger.error("SX1276: Failed to open GPIO#{pin}: #{inspect(reason)}")
        # Clean up any previously opened resources
        cleanup_resources(cleanup_on_fail)
        {:error, reason}
    end
  end

  defp cleanup_resources(resources) do
    Enum.each(resources, fn resource ->
      try do
        # Try SPI close first, then GPIO
        case Circuits.SPI.close(resource) do
          :ok -> :ok
          _ -> Circuits.GPIO.close(resource)
        end
      rescue
        _ -> :ok
      end
    end)
  end
end
