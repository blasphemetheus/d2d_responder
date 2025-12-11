defmodule D2dResponder.LoRa do
  @moduledoc """
  GenServer for RN2483 LoRa module communication.
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
       buffer: "",
       subscribers: []
     }}
  end

  @impl true
  def handle_info({:circuits_uart, _port, data}, state) when is_binary(data) do
    new_buffer = state.buffer <> data

    case String.split(new_buffer, "\r\n", parts: 2) do
      [response, rest] ->
        response = String.trim(response)

        if state.pending_response do
          GenServer.reply(state.pending_response, {:ok, response})
        end

        # Notify subscribers of async events
        handle_async_response(response, state.subscribers)

        {:noreply, %{state | buffer: rest, pending_response: nil}}

      [_incomplete] ->
        {:noreply, %{state | buffer: new_buffer}}
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

    case Circuits.UART.open(uart, port, speed: @default_baud, active: true) do
      :ok ->
        Circuits.UART.flush(uart)
        Process.sleep(100)
        Logger.info("Connected to #{port}")
        {:reply, :ok, %{state | uart: uart, port: port, connected: true, buffer: ""}}

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
      Circuits.UART.write(state.uart, "#{cmd}\r\n")
      {:noreply, %{state | pending_response: from, buffer: ""}}
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
