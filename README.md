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

### LoRa Commands

```elixir
# Connect to LoRa module
D2dResponder.connect()

# Start beacon mode (transmit periodic messages)
D2dResponder.beacon()
D2dResponder.beacon(message: "HELLO", interval: 3000)

# Start echo mode (receive and echo back)
D2dResponder.echo()

# Stop modes
D2dResponder.stop_beacon()
D2dResponder.stop_echo()

# Check status
D2dResponder.status()
```

## IP Addresses

| Technology | Pi (this device) | Laptop |
|------------|------------------|--------|
| WiFi Ad-hoc | 192.168.12.1 | 192.168.12.2 |
| Bluetooth PAN | 192.168.44.1 | 192.168.44.2 |
