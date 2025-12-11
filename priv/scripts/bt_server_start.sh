#!/bin/bash
# Bluetooth PAN NAP server start script for Raspberry Pi
# Usage: sudo bt_server_start.sh [ip]
set -e

IP=${1:-192.168.44.1}

echo "Starting Bluetooth PAN NAP server..."

# Ensure bluetooth is running
systemctl start bluetooth 2>/dev/null || true
sleep 1

# Make discoverable and pairable
bluetoothctl power on
bluetoothctl discoverable on
bluetoothctl pairable on

# Start NAP server (bt-network from bluez-tools)
# Kill any existing instance first
pkill -f "bt-network -s nap" 2>/dev/null || true
sleep 1

bt-network -s nap pan0 &
sleep 2

# Configure pan0 interface
ip link set pan0 up 2>/dev/null || true
ip addr flush dev pan0 2>/dev/null || true
ip addr add "$IP/24" dev pan0 2>/dev/null || true

echo "OK: Bluetooth NAP server running on pan0 at $IP"
