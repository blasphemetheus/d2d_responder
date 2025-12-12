defmodule D2dResponder.Echo do
  @moduledoc """
  Listens for LoRa messages and echoes them back with a prefix.
  Works with both RN2903 (UART) and SX1276 (SPI) backends.
  """
  use GenServer
  require Logger
  alias D2dResponder.{LoRa, LoRaHAT}

  @default_prefix "ECHO:"
  # Delay before echoing to allow sender to switch to RX mode (half-duplex turnaround)
  @echo_delay_ms 150

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_echo(opts \\ []) do
    GenServer.call(__MODULE__, {:start, opts})
  end

  def stop_echo do
    GenServer.call(__MODULE__, :stop)
  end

  def set_prefix(prefix) do
    GenServer.call(__MODULE__, {:set_prefix, prefix})
  end

  def status do
    GenServer.call(__MODULE__, :status)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok,
     %{
       running: false,
       prefix: @default_prefix,
       rx_count: 0,
       tx_count: 0
     }}
  end

  @impl true
  def handle_call({:start, opts}, _from, state) do
    if state.running do
      {:reply, {:error, :already_running}, state}
    else
      prefix = Keyword.get(opts, :prefix, state.prefix)
      backend = Application.get_env(:d2d_responder, :lora_backend, :rn2903)

      # Log current radio settings for debugging
      Logger.info("Echo: Starting with backend=#{backend}, prefix='#{prefix}'")
      case lora_module().get_radio_settings() do
        {:ok, settings} ->
          Logger.info("Echo: Radio settings: #{inspect(settings)}")
        _ ->
          Logger.warning("Echo: Could not read radio settings")
      end

      # Subscribe to LoRa RX events from the active backend
      lora_module().subscribe(self())

      # Start continuous RX mode
      start_listening()

      Logger.info("Echo mode started - waiting for packets...")

      {:reply, :ok, %{state | running: true, prefix: prefix, rx_count: 0, tx_count: 0}}
    end
  end

  @impl true
  def handle_call(:stop, _from, state) do
    # Unsubscribe from LoRa events
    lora_module().unsubscribe(self())
    Logger.info("Echo stopped. RX: #{state.rx_count}, TX: #{state.tx_count}")
    {:reply, :ok, %{state | running: false}}
  end

  @impl true
  def handle_call({:set_prefix, prefix}, _from, state) do
    {:reply, :ok, %{state | prefix: prefix}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply,
     %{
       running: state.running,
       prefix: state.prefix,
       rx_count: state.rx_count,
       tx_count: state.tx_count
     }, state}
  end

  # Handle RX from both backends (slightly different message format)
  @impl true
  def handle_info({:lora_rx, data, hex}, state) do
    handle_rx(data, hex, state)
  end

  # SX1276 sends additional opts
  @impl true
  def handle_info({:lora_rx, data, hex, _opts}, state) do
    handle_rx(data, hex, state)
  end

  @impl true
  def handle_info({:do_echo, response}, state) do
    if state.running do
      case lora_module().transmit(response) do
        {:ok, _} ->
          printable = if String.printable?(response), do: response, else: "[binary data]"
          Logger.debug("Echo TX: #{printable}")
          # Don't start listening here - wait for lora_tx_ok/lora_tx_error
          {:noreply, %{state | tx_count: state.tx_count + 1}}

        {:error, reason} ->
          Logger.warning("Echo TX failed: #{inspect(reason)}")
          start_listening()
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:lora_tx_ok, state) do
    if state.running do
      # Resume listening after successful TX
      start_listening()
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:lora_tx_error, state) do
    if state.running do
      Logger.warning("Echo TX error, resuming listen")
      start_listening()
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:start_rx, state) do
    if state.running do
      start_listening()
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:do_start_rx, state) do
    if state.running do
      backend = Application.get_env(:d2d_responder, :lora_backend, :rn2903)
      Logger.info("Echo: entering RX mode (backend=#{backend}, rx_count=#{state.rx_count}, tx_count=#{state.tx_count})")

      case lora_module().receive_mode(0) do
        {:ok, _} ->
          Logger.info("Echo: now listening for packets...")

        :ok ->
          Logger.info("Echo: now listening for packets...")

        {:error, reason} ->
          Logger.warning("Echo: failed to start RX: #{inspect(reason)}")
          # Retry after delay
          Process.send_after(self(), :do_start_rx, 1000)
      end
    end

    {:noreply, state}
  end

  # Private

  defp handle_rx(data, hex, state) do
    if state.running do
      # Use hex for logging to avoid UTF-8 issues with binary data
      printable = if String.printable?(data), do: data, else: "[binary]"
      Logger.info("Echo RX: #{printable} (#{hex})")

      # Schedule echo with delay to allow sender to switch to RX mode
      response = state.prefix <> data
      Process.send_after(self(), {:do_echo, response}, @echo_delay_ms)

      {:noreply, %{state | rx_count: state.rx_count + 1}}
    else
      {:noreply, state}
    end
  end

  defp start_listening do
    # Small delay before starting RX to let TX complete
    Process.send_after(self(), :do_start_rx, 100)
  end

  defp lora_module do
    case Application.get_env(:d2d_responder, :lora_backend, :rn2903) do
      :sx1276 -> LoRaHAT
      _ -> LoRa
    end
  end
end
