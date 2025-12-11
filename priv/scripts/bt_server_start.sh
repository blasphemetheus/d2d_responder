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

# Create pan0 bridge interface BEFORE starting bt-network
# This is required for bt-network to properly attach bnep connections
ip link del pan0 2>/dev/null || true
ip link add name pan0 type bridge
ip link set pan0 up
ip addr add "$IP/24" dev pan0

echo "Created pan0 bridge interface with IP $IP"

# Start bt-network with nohup so it detaches completely
nohup bt-network -s nap pan0 >/dev/null 2>&1 &
sleep 2

echo "OK: Bluetooth NAP server running on pan0 at $IP"
exit 0
