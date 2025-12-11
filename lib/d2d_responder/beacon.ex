defmodule D2dResponder.Beacon do
  @moduledoc """
  Periodically transmits beacon messages via LoRa.
  """
  use GenServer
  require Logger
  alias D2dResponder.LoRa

  @default_interval 5_000
  @default_message "BEACON"

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_beacon(opts \\ []) do
    GenServer.call(__MODULE__, {:start, opts})
  end

  def stop_beacon do
    GenServer.call(__MODULE__, :stop)
  end

  def set_message(message) do
    GenServer.call(__MODULE__, {:set_message, message})
  end

  def set_interval(interval_ms) do
    GenServer.call(__MODULE__, {:set_interval, interval_ms})
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
       message: @default_message,
       interval: @default_interval,
       timer_ref: nil,
       tx_count: 0
     }}
  end

  @impl true
  def handle_call({:start, opts}, _from, state) do
    if state.running do
      {:reply, {:error, :already_running}, state}
    else
      message = Keyword.get(opts, :message, state.message)
      interval = Keyword.get(opts, :interval, state.interval)

      # Send first beacon immediately
      send(self(), :send_beacon)

      Logger.info("Beacon started: '#{message}' every #{interval}ms")

      {:reply, :ok,
       %{state | running: true, message: message, interval: interval, tx_count: 0}}
    end
  end

  @impl true
  def handle_call(:stop, _from, state) do
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    Logger.info("Beacon stopped after #{state.tx_count} transmissions")
    {:reply, :ok, %{state | running: false, timer_ref: nil}}
  end

  @impl true
  def handle_call({:set_message, message}, _from, state) do
    {:reply, :ok, %{state | message: message}}
  end

  @impl true
  def handle_call({:set_interval, interval}, _from, state) do
    {:reply, :ok, %{state | interval: interval}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply,
     %{
       running: state.running,
       message: state.message,
       interval: state.interval,
       tx_count: state.tx_count
     }, state}
  end

  @impl true
  def handle_info(:send_beacon, state) do
    if state.running do
      # Transmit the beacon
      case LoRa.transmit(state.message) do
        {:ok, _} ->
          Logger.debug("Beacon TX ##{state.tx_count + 1}: #{state.message}")

        {:error, reason} ->
          Logger.warning("Beacon TX failed: #{inspect(reason)}")
      end

      # Schedule next beacon
      timer_ref = Process.send_after(self(), :send_beacon, state.interval)

      {:noreply, %{state | timer_ref: timer_ref, tx_count: state.tx_count + 1}}
    else
      {:noreply, state}
    end
  end
end
