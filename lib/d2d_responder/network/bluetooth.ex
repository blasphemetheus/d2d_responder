defmodule D2dResponder.Network.Bluetooth do
  @moduledoc """
  GenServer for Bluetooth PAN NAP server on Raspberry Pi.
  Auto-starts NAP server on init.
  """
  use GenServer
  require Logger

  @default_ip "192.168.44.1"
  @peer_ip "192.168.44.2"

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_server(ip \\ @default_ip) do
    GenServer.call(__MODULE__, {:start_server, ip}, 30_000)
  end

  def stop_server do
    GenServer.call(__MODULE__, :stop_server, 30_000)
  end

  def connected? do
    GenServer.call(__MODULE__, :connected?)
  end

  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  def get_peer_ip do
    @peer_ip
  end

  @doc """
  Reset Bluetooth to normal state.
  Call this from IEx: D2dResponder.Network.Bluetooth.reset()
  """
  def reset do
    GenServer.call(__MODULE__, :reset, 30_000)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    state = %{
      connected: false,
      ip: @default_ip,
      peer_ip: @peer_ip,
      auto_start: Keyword.get(opts, :auto_start, false)
    }

    # Auto-start Bluetooth NAP server if configured
    if state.auto_start do
      send(self(), :auto_setup)
    end

    {:ok, state}
  end

  @impl true
  def handle_info(:auto_setup, state) do
    Logger.info("Bluetooth: Auto-starting NAP server...")
    case do_start_server(state.ip) do
      :ok ->
        Logger.info("Bluetooth: NAP server started on pan0 at #{state.ip}")
        D2dResponder.FileLogger.log_event("BT_SERVER_STARTED: pan0 at #{state.ip}")
        {:noreply, %{state | connected: true}}

      {:error, reason} ->
        Logger.error("Bluetooth: Auto-setup failed: #{inspect(reason)}")
        # Retry after 5 seconds
        Process.send_after(self(), :auto_setup, 5_000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_call({:start_server, ip}, _from, state) do
    case do_start_server(ip) do
      :ok ->
        D2dResponder.FileLogger.log_event("BT_SERVER_STARTED: pan0 at #{ip}")
        {:reply, :ok, %{state | ip: ip, connected: true}}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:stop_server, _from, state) do
    do_stop_server()
    D2dResponder.FileLogger.log_event("BT_SERVER_STOPPED")
    {:reply, :ok, %{state | connected: false}}
  end

  @impl true
  def handle_call(:connected?, _from, state) do
    {:reply, state.connected, state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      connected: state.connected,
      mode: :server,
      interface: "pan0",
      ip: state.ip,
      peer_ip: state.peer_ip
    }
    {:reply, status, state}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    Logger.info("Bluetooth: Resetting to normal state...")
    do_stop_server()
    do_reset_bluetooth()
    D2dResponder.FileLogger.log_event("BT_RESET: Bluetooth service restarted")
    {:reply, :ok, %{state | connected: false}}
  end

  @impl true
  def terminate(_reason, state) do
    if state.connected do
      Logger.info("Bluetooth: Cleaning up NAP server...")
      do_stop_server()
    end
    :ok
  end

  # Private functions

  defp do_start_server(ip) do
    script = scripts_path("bt_server_start.sh")
    Logger.info("Bluetooth: Running script #{script} with IP #{ip}")
    Logger.info("Bluetooth: Script exists? #{File.exists?(script)}")

    # Use Port.open instead of System.cmd to avoid potential hanging
    try do
      port = Port.open({:spawn_executable, "/usr/bin/sudo"}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: [script, ip]
      ])

      receive do
        {^port, {:data, data}} ->
          Logger.info("Bluetooth script output: #{data}")
          receive do
            {^port, {:exit_status, 0}} ->
              Logger.info("Bluetooth: Script completed successfully")
              :ok
            {^port, {:exit_status, code}} ->
              Logger.error("Bluetooth: Script exited with code #{code}")
              {:error, "exit code #{code}"}
          after
            25_000 ->
              Port.close(port)
              Logger.error("Bluetooth: Timed out waiting for exit status")
              {:error, "timeout"}
          end

        {^port, {:exit_status, 0}} ->
          Logger.info("Bluetooth: Script completed successfully (no output)")
          :ok

        {^port, {:exit_status, code}} ->
          Logger.error("Bluetooth: Script exited with code #{code}")
          {:error, "exit code #{code}"}
      after
        25_000 ->
          Port.close(port)
          Logger.error("Bluetooth: Timed out waiting for script")
          {:error, "timeout"}
      end
    rescue
      e ->
        Logger.error("Bluetooth server start exception: #{inspect(e)}")
        {:error, inspect(e)}
    end
  end

  defp do_stop_server do
    script = scripts_path("bt_server_stop.sh")

    task = Task.async(fn ->
      System.cmd("sudo", [script], stderr_to_stdout: true)
    end)

    case Task.yield(task, 10_000) || Task.shutdown(task) do
      {:ok, {output, 0}} ->
        Logger.debug("Bluetooth server stop output: #{output}")
        :ok

      {:ok, {output, code}} ->
        Logger.warning("Bluetooth server stop issue (exit #{code}): #{output}")
        :ok

      nil ->
        Logger.warning("Bluetooth server stop timed out")
        :ok
    end
  end

  defp do_reset_bluetooth do
    # Restart bluetooth service to clear any stuck state
    # Use timeout to avoid hanging
    task = Task.async(fn ->
      System.cmd("sudo", ["systemctl", "restart", "bluetooth"], stderr_to_stdout: true)
    end)

    case Task.yield(task, 10_000) || Task.shutdown(task) do
      {:ok, {output, 0}} ->
        Logger.debug("Bluetooth restart output: #{output}")
        :ok

      {:ok, {output, code}} ->
        Logger.warning("Bluetooth restart issue (exit #{code}): #{output}")
        :ok

      nil ->
        Logger.warning("Bluetooth restart timed out, continuing anyway")
        :ok
    end
  end

  defp scripts_path(script_name) do
    :code.priv_dir(:d2d_responder)
    |> to_string()
    |> Path.join("scripts/#{script_name}")
  end
end
