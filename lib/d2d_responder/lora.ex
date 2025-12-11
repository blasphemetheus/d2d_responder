defmodule D2dResponder.LoRa do
  @moduledoc """
  GenServer for RN2903 LoRa module communication.

  The RN2903 uses 57600 baud, 8N1, and requires CRLF line endings
  for both commands and responses.
  """
  use GenServer
  require Logger

  @default_port "/dev/ttyACM0"
  @default_baud 57600

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def connect(port \\ @default_port) do
    GenServer.call(__MODULE__, {:connect, port})
  end

  def disconnect do
    GenServer.call(__MODULE__, :disconnect)
  end

  def send_command(cmd, timeout \\ 3_000) do
    GenServer.call(__MODULE__, {:send_command, cmd}, timeout)
  end

  def pause_mac do
    send_command("mac pause")
  end

  def transmit(data) when is_binary(data) do
    hex = Base.encode16(data)
    D2dResponder.FileLogger.log_tx(data, hex)
    send_command("radio tx #{hex}")
  end

  def receive_mode(timeout_ms \\ 0) do
    send_command("radio rx #{timeout_ms}")
  end

  def set_frequency(freq) do
    send_command("radio set freq #{freq}")
  end

  def set_spreading_factor(sf) when sf in 7..12 do
    send_command("radio set sf sf#{sf}")
  end

  def set_bandwidth(bw) when bw in [125, 250, 500] do
    send_command("radio set bw #{bw}")
  end

  def set_power(pwr) when pwr in -3..14 do
    send_command("radio set pwr #{pwr}")
  end

  def connected? do
    GenServer.call(__MODULE__, :connected?)
  end

  def subscribe(pid) do
    GenServer.call(__MODULE__, {:subscribe, pid})
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok,
     %{
       uart: nil,
       port: nil,
       connected: false,
       pending_response: nil,
       subscribers: []
     }}
  end

  @impl true
  def handle_info({:circuits_uart, _port, {:partial, partial}}, state) do
    # Partial line received (framing mode)
    Logger.debug("UART partial: #{inspect(partial)}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:circuits_uart, _port, data}, state) when is_binary(data) do
    # With line framing, we get complete lines
    response = String.trim(data)
    Logger.debug("UART RX: #{inspect(response)}")

    if response != "" do
      if state.pending_response do
        GenServer.reply(state.pending_response, {:ok, response})
      end

      # Notify subscribers of async events
      handle_async_response(response, state.subscribers)

      {:noreply, %{state | pending_response: nil}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:circuits_uart, _port, {:error, reason}}, state) do
    Logger.error("UART error: #{inspect(reason)}")
    {:noreply, %{state | connected: false}}
  end

  @impl true
  def handle_call({:connect, port}, _from, state) do
    if state.uart, do: Circuits.UART.close(state.uart)

    {:ok, uart} = Circuits.UART.start_link()

    # RN2903 settings: 57600 baud, 8N1, no flow control, CRLF line endings
    uart_opts = [
      speed: @default_baud,
      data_bits: 8,
      stop_bits: 1,
      parity: :none,
      flow_control: :none,
      active: true,
      framing: {Circuits.UART.Framing.Line, separator: "\r\n"}
    ]

    case Circuits.UART.open(uart, port, uart_opts) do
      :ok ->
        # Wake up the module and verify communication
        case wake_up_module(uart) do
          {:ok, version} ->
            Logger.info("Connected to #{port} - #{version}")
            {:reply, :ok, %{state | uart: uart, port: port, connected: true}}

          {:error, reason} ->
            Logger.error("Failed to wake up LoRa module: #{inspect(reason)}")
            Circuits.UART.close(uart)
            Circuits.UART.stop(uart)
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        Circuits.UART.stop(uart)
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:disconnect, _from, state) do
    if state.uart, do: Circuits.UART.close(state.uart)
    {:reply, :ok, %{state | uart: nil, port: nil, connected: false}}
  end

  @impl true
  def handle_call({:send_command, cmd}, from, state) do
    if state.connected do
      Logger.debug("UART TX: #{inspect(cmd)}")
      # RN2903 expects commands terminated with CRLF
      Circuits.UART.write(state.uart, "#{cmd}\r\n")
      {:noreply, %{state | pending_response: from}}
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  @impl true
  def handle_call(:connected?, _from, state) do
    {:reply, state.connected, state}
  end

  @impl true
  def handle_call({:subscribe, pid}, _from, state) do
    {:reply, :ok, %{state | subscribers: [pid | state.subscribers]}}
  end

  # Private

  defp wake_up_module(uart) do
    # Flush any garbage and send wake-up CRLFs
    Circuits.UART.flush(uart)
    Circuits.UART.write(uart, "\r\n\r\n\r\n")
    Process.sleep(100)
    Circuits.UART.flush(uart)
    drain_uart_messages()

    # Try to get version - first attempt often fails or returns invalid_param
    # Retry up to 3 times
    Enum.reduce_while(1..3, {:error, :no_response}, fn attempt, _acc ->
      Logger.debug("Wake-up attempt #{attempt}")
      Circuits.UART.write(uart, "sys get ver\r\n")

      case wait_for_response(2000) do
        {:ok, "RN" <> _ = version} ->
          {:halt, {:ok, version}}

        {:ok, "invalid_param"} ->
          # First command often fails, try again
          Process.sleep(100)
          {:cont, {:error, :invalid_param}}

        {:ok, other} ->
          Logger.warning("Unexpected wake-up response: #{inspect(other)}")
          Process.sleep(100)
          {:cont, {:error, {:unexpected, other}}}

        {:error, :timeout} ->
          Process.sleep(200)
          {:cont, {:error, :timeout}}
      end
    end)
  end

  defp wait_for_response(timeout) do
    receive do
      {:circuits_uart, _port, {:partial, _}} ->
        # Ignore partials, keep waiting
        wait_for_response(timeout)

      {:circuits_uart, _port, data} when is_binary(data) ->
        {:ok, String.trim(data)}

      {:circuits_uart, _port, {:error, reason}} ->
        {:error, reason}
    after
      timeout -> {:error, :timeout}
    end
  end

  defp drain_uart_messages do
    receive do
      {:circuits_uart, _, _} -> drain_uart_messages()
    after
      0 -> :ok
    end
  end

  defp handle_async_response("radio_rx " <> hex, subscribers) do
    case Base.decode16(hex, case: :mixed) do
      {:ok, data} ->
        D2dResponder.FileLogger.log_rx(data, hex)
        for pid <- subscribers, do: send(pid, {:lora_rx, data, hex})

      :error ->
        Logger.warning("Invalid RX hex: #{hex}")
    end
  end

  defp handle_async_response("radio_tx_ok", subscribers) do
    D2dResponder.FileLogger.log_event(:tx_ok)
    for pid <- subscribers, do: send(pid, :lora_tx_ok)
  end

  defp handle_async_response("radio_err", subscribers) do
    D2dResponder.FileLogger.log_event(:tx_error)
    for pid <- subscribers, do: send(pid, :lora_tx_error)
  end

  defp handle_async_response(_other, _subscribers), do: :ok
end
