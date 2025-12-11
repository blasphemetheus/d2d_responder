#!/bin/bash
# Bluetooth PAN NAP server start script for Raspberry Pi
# Usage: sudo bt_server_start.sh [ip]

IP=${1:-192.168.44.1}

echo "Starting Bluetooth PAN NAP server..."

# Ensure bluetooth is running
systemctl start bluetooth 2>/dev/null || true
sleep 1

# Make discoverable and pairable (use echo to avoid interactive mode)
echo -e "power on\ndiscoverable on\npairable on\nquit" | bluetoothctl >/dev/null 2>&1 || true
sleep 1

# Start NAP server (bt-network from bluez-tools)
# Kill any existing instance first
pkill -f "bt-network -s nap" 2>/dev/null || true
sleep 1

# Check if bt-network exists
if ! command -v bt-network &> /dev/null; then
    echo "ERROR: bt-network not found. Install with: sudo apt install bluez-tools"
    exit 1
fi

bt-network -s nap pan0 &
sleep 2

# Configure pan0 interface
ip link set pan0 up 2>/dev/null || true
ip addr flush dev pan0 2>/dev/null || true
ip addr add "$IP/24" dev pan0 2>/dev/null || true

echo "OK: Bluetooth NAP server running on pan0 at $IP"
