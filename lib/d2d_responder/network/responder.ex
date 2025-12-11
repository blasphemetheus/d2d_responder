defmodule D2dResponder.Network.Responder do
  @moduledoc """
  GenServer that manages iperf3 server for throughput testing.
  Auto-starts iperf3 server on init.
  """
  use GenServer
  require Logger

  @default_port 5201

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_iperf_server(port \\ @default_port) do
    GenServer.call(__MODULE__, {:start_iperf, port})
  end

  def stop_iperf_server do
    GenServer.call(__MODULE__, :stop_iperf)
  end

  def iperf_running? do
    GenServer.call(__MODULE__, :iperf_running?)
  end

  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    state = %{
      iperf_port: nil,
      iperf_pid: nil,
      auto_start: Keyword.get(opts, :auto_start, true)
    }

    # Auto-start iperf3 server
    if state.auto_start do
      send(self(), :auto_start_iperf)
    end

    {:ok, state}
  end

  @impl true
  def handle_info(:auto_start_iperf, state) do
    # Check if already running from previous session
    if port_in_use?(@default_port) do
      Logger.info("Responder: iperf3 already running on port #{@default_port}, killing it first...")
      kill_existing_iperf(@default_port)
      # Small delay then retry
      Process.send_after(self(), :auto_start_iperf, 1_000)
      {:noreply, state}
    else
      Logger.info("Responder: Auto-starting iperf3 server...")
      case do_start_iperf(@default_port) do
        {:ok, port} ->
          Logger.info("Responder: iperf3 server running on port #{@default_port}")
          D2dResponder.FileLogger.log_event("IPERF_SERVER_STARTED: port #{@default_port}")
          {:noreply, %{state | iperf_port: @default_port, iperf_pid: port}}

        {:error, reason} ->
          Logger.error("Responder: Failed to start iperf3: #{inspect(reason)}")
          # Don't retry endlessly - just log and give up
          {:noreply, state}
      end
    end
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, state) when is_port(port) do
    Logger.warning("Responder: iperf3 exited with status #{status}")
    # Restart iperf3 server
    Process.send_after(self(), :auto_start_iperf, 1_000)
    {:noreply, %{state | iperf_port: nil, iperf_pid: nil}}
  end

  @impl true
  def handle_info({port, {:data, data}}, state) when is_port(port) do
    Logger.debug("iperf3: #{data}")
    {:noreply, state}
  end

  @impl true
  def handle_call({:start_iperf, port_num}, _from, state) do
    # Stop existing server if running
    if state.iperf_pid do
      do_stop_iperf(state.iperf_pid)
    end

    case do_start_iperf(port_num) do
      {:ok, port} ->
        D2dResponder.FileLogger.log_event("IPERF_SERVER_STARTED: port #{port_num}")
        {:reply, :ok, %{state | iperf_port: port_num, iperf_pid: port}}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:stop_iperf, _from, state) do
    if state.iperf_pid do
      do_stop_iperf(state.iperf_pid)
      D2dResponder.FileLogger.log_event("IPERF_SERVER_STOPPED")
    end
    {:reply, :ok, %{state | iperf_port: nil, iperf_pid: nil}}
  end

  @impl true
  def handle_call(:iperf_running?, _from, state) do
    {:reply, state.iperf_pid != nil, state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      running: state.iperf_pid != nil,
      port: state.iperf_port
    }
    {:reply, status, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.iperf_pid do
      Logger.info("Responder: Stopping iperf3 server...")
      do_stop_iperf(state.iperf_pid)
    end
    :ok
  end

  # Private functions

  defp do_start_iperf(port_num) do
    # Check if iperf3 is available
    case System.find_executable("iperf3") do
      nil ->
        {:error, "iperf3 not found in PATH"}

      _path ->
        # Start iperf3 server as a port
        port = Port.open(
          {:spawn_executable, System.find_executable("iperf3")},
          [
            :binary,
            :exit_status,
            args: ["-s", "-p", to_string(port_num)]
          ]
        )
        {:ok, port}
    end
  end

  defp do_stop_iperf(port) when is_port(port) do
    Port.close(port)
  rescue
    _ -> :ok
  end

  defp do_stop_iperf(_), do: :ok

  defp port_in_use?(port_num) do
    case System.cmd("ss", ["-tln", "sport = :#{port_num}"], stderr_to_stdout: true) do
      {output, 0} ->
        # If output has more than just the header, port is in use
        String.contains?(output, "LISTEN")
      _ ->
        false
    end
  end

  defp kill_existing_iperf(port_num) do
    # Find and kill any process using this port
    case System.cmd("fuser", ["-k", "#{port_num}/tcp"], stderr_to_stdout: true) do
      {_, 0} -> :ok
      _ ->
        # Also try pkill as fallback
        System.cmd("pkill", ["-f", "iperf3.*#{port_num}"], stderr_to_stdout: true)
        :ok
    end
  end
end
