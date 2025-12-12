# D2D Responder

Raspberry Pi responder for D2D (Device-to-Device) communication testing. Provides LoRa beacon/echo modes and network services for WiFi ad-hoc and Bluetooth PAN testing.

## Setup

### Dependencies

```bash
# Install system dependencies
sudo apt install iperf3 iw bluez-tools

# Install Elixir dependencies
mix deps.get
mix compile
```

### Sudoers Configuration

The network scripts require sudo access without password prompts. Run:

```bash
sudo visudo -f /etc/sudoers.d/d2d
```

Add these lines (adjust username and path as needed):

```
dori ALL=(ALL) NOPASSWD: /home/dori/d2d_responder/priv/scripts/*.sh
dori ALL=(ALL) NOPASSWD: /home/dori/d2d_responder/_build/dev/lib/d2d_responder/priv/scripts/*.sh
dori ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart NetworkManager
dori ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart bluetooth
dori ALL=(ALL) NOPASSWD: /usr/bin/systemctl start bluetooth
dori ALL=(ALL) NOPASSWD: /usr/bin/pkill
dori ALL=(ALL) NOPASSWD: /usr/bin/fuser
```

## Usage

Start the application:

```bash
iex -S mix
```

### Network Services (WiFi/Bluetooth/iperf3)

```elixir
# Start all network services for field testing
D2dResponder.start_network()

# Check status
D2dResponder.network_status()

# Reset to normal state (instead of rebooting)
D2dResponder.reset_network()
```

### Terminal UI (Recommended)

The TUI provides an interactive menu for all operations:

```bash
# Start with TUI
iex -S mix

# Then run
D2dResponder.TUI.run()

# Or start directly in echo mode (for unattended operation)
iex -S mix -- --echo
```

### Supported LoRa Hardware

The responder supports two LoRa hardware backends:

| Hardware | Interface | Notes |
|----------|-----------|-------|
| **RN2903** | USB Serial (`/dev/ttyACM0`) | Microchip PICtail, Moteino USB |
| **SX1276** | SPI + GPIO | Dragino LoRa/GPS HAT |

Select the hardware type when connecting via the TUI (`[l] LoRa: Connect`).

#### Dragino LoRa/GPS HAT Setup

The SX1276 HAT requires SPI enabled on the Pi:

```bash
# Enable SPI via raspi-config
sudo raspi-config
# -> Interface Options -> SPI -> Enable

# Verify SPI is available
ls /dev/spidev*
# Should show: /dev/spidev0.0  /dev/spidev0.1

# Check GPIO permissions (user should be in gpio group)
groups
# Should include: gpio

# If not in gpio group:
sudo usermod -aG gpio $USER
# Then logout/login
```

**Dragino HAT Pinout:**

| Function | BCM Pin | Physical Pin |
|----------|---------|--------------|
| MOSI     | 10      | 19           |
| MISO     | 9       | 21           |
| SCLK     | 11      | 23           |
| NSS/CS   | 25      | 22           |
| RESET    | 17      | 11           |
| DIO0     | 4       | 7            |

### LoRa Commands (Programmatic)

```elixir
# Connect to LoRa module (RN2903 via USB)
D2dResponder.LoRa.connect("/dev/ttyACM0")

# Or for Dragino HAT (SX1276 via SPI)
D2dResponder.LoRaHAT.start_link()
D2dResponder.LoRaHAT.connect()

# Start beacon mode (transmit periodic messages)
D2dResponder.Beacon.start_beacon()
D2dResponder.Beacon.start_beacon(message: "HELLO", interval: 3000)

# Start echo mode (receive and echo back)
D2dResponder.Echo.start_echo()

# Stop modes
D2dResponder.Beacon.stop_beacon()
D2dResponder.Echo.stop_echo()

# Check status
D2dResponder.Echo.status()
D2dResponder.Beacon.status()
```

## IP Addresses

| Technology | Pi (this device) | Laptop |
|------------|------------------|--------|
| WiFi Ad-hoc | 192.168.12.1 | 192.168.12.2 |
| Bluetooth PAN | 192.168.44.1 | 192.168.44.2 |
