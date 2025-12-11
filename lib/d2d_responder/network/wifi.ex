defmodule D2dResponder.Network.WiFi do
  @moduledoc """
  GenServer for WiFi ad-hoc network management on Raspberry Pi.
  Auto-starts ad-hoc network on init.
  """
  use GenServer
  require Logger

  @default_interface "wlan0"
  @default_ssid "PiAdhoc"
  @default_freq "2437"
  @default_ip "192.168.12.1"
  @peer_ip "192.168.12.2"

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def setup(interface \\ @default_interface) do
    GenServer.call(__MODULE__, {:setup, interface}, 30_000)
  end

  def teardown do
    GenServer.call(__MODULE__, :teardown, 30_000)
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
  Reset WiFi to normal state (restore NetworkManager).
  Call this from IEx: D2dResponder.Network.WiFi.reset()
  """
  def reset do
    GenServer.call(__MODULE__, :reset, 30_000)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    state = %{
      interface: Keyword.get(opts, :interface, @default_interface),
      connected: false,
      ip: @default_ip,
      peer_ip: @peer_ip,
      auto_start: Keyword.get(opts, :auto_start, true)
    }

    # Auto-start WiFi ad-hoc if configured
    if state.auto_start do
      send(self(), :auto_setup)
    end

    {:ok, state}
  end

  @impl true
  def handle_info(:auto_setup, state) do
    Logger.info("WiFi: Auto-starting ad-hoc network...")
    case do_setup(state.interface) do
      :ok ->
        Logger.info("WiFi: Ad-hoc network started on #{state.interface} at #{state.ip}")
        D2dResponder.FileLogger.log_event("WIFI_CONNECTED: #{state.interface} at #{state.ip}")
        {:noreply, %{state | connected: true}}

      {:error, reason} ->
        Logger.error("WiFi: Auto-setup failed: #{inspect(reason)}")
        # Retry after 5 seconds
        Process.send_after(self(), :auto_setup, 5_000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_call({:setup, interface}, _from, state) do
    case do_setup(interface) do
      :ok ->
        D2dResponder.FileLogger.log_event("WIFI_CONNECTED: #{interface} at #{state.ip}")
        {:reply, :ok, %{state | interface: interface, connected: true}}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:teardown, _from, state) do
    do_teardown(state.interface)
    D2dResponder.FileLogger.log_event("WIFI_DISCONNECTED: #{state.interface}")
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
      interface: state.interface,
      ip: state.ip,
      peer_ip: state.peer_ip
    }
    {:reply, status, state}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    Logger.info("WiFi: Resetting to normal state...")
    do_reset(state.interface)
    D2dResponder.FileLogger.log_event("WIFI_RESET: NetworkManager restored")
    {:reply, :ok, %{state | connected: false}}
  end

  @impl true
  def terminate(_reason, state) do
    if state.connected do
      Logger.info("WiFi: Cleaning up ad-hoc network...")
      do_teardown(state.interface)
    end
    :ok
  end

  # Private functions

  defp do_setup(interface) do
    script = scripts_path("wifi_setup.sh")
    args = [interface, @default_ssid, @default_freq, @default_ip]

    case System.cmd("sudo", [script | args], stderr_to_stdout: true) do
      {output, 0} ->
        Logger.debug("WiFi setup output: #{output}")
        :ok

      {output, code} ->
        Logger.error("WiFi setup failed (exit #{code}): #{output}")
        {:error, output}
    end
  end

  defp do_teardown(interface) do
    script = scripts_path("wifi_teardown.sh")

    case System.cmd("sudo", [script, interface], stderr_to_stdout: true) do
      {output, 0} ->
        Logger.debug("WiFi teardown output: #{output}")
        :ok

      {output, code} ->
        Logger.warning("WiFi teardown issue (exit #{code}): #{output}")
        :ok
    end
  end

  defp do_reset(interface) do
    # First teardown ad-hoc, then restart NetworkManager
    do_teardown(interface)
    case System.cmd("sudo", ["systemctl", "restart", "NetworkManager"], stderr_to_stdout: true) do
      {output, 0} ->
        Logger.debug("NetworkManager restart output: #{output}")
        :ok

      {output, code} ->
        Logger.warning("NetworkManager restart issue (exit #{code}): #{output}")
        :ok
    end
  end

  defp scripts_path(script_name) do
    :code.priv_dir(:d2d_responder)
    |> to_string()
    |> Path.join("scripts/#{script_name}")
  end
end
