#!/bin/bash
# Bluetooth PAN NAP server stop script
# Usage: sudo bt_server_stop.sh
set -e

echo "Stopping Bluetooth PAN NAP server..."

# Kill bt-network process
pkill -f "bt-network -s nap" 2>/dev/null || true

# Clean up pan0 interface
ip link set pan0 down 2>/dev/null || true

# Turn off discoverable
bluetoothctl discoverable off 2>/dev/null || true

echo "OK: Bluetooth NAP server stopped"
