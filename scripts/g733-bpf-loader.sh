#!/bin/bash
# G733 HID-BPF Automated Loader Script
# Triggered by udev
# $1 = DEVPATH (e.g. /devices/pci0000:00/.../0003:046D:0B1F.0004)

if [ -z "$1" ]; then
    echo "Usage: $0 <DEVPATH>"
    exit 1
fi

LOG_FILE="/var/log/g733-bpf-loader.log"
exec >> "$LOG_FILE" 2>&1
echo "=== $(date) ==="
echo "Triggered for DEVPATH: $1"

# Extract the sysfs ID (the last part of the path after the dot)
# e.g., 0003:046D:0B1F.0004 -> 0004, which is in hexadecimal
DEV_NAME=$(basename "$1")
HID_HEX=$(echo "$DEV_NAME" | cut -d'.' -f2)

# Hex to decimal conversion
HID_ID=$((16#$HID_HEX))
echo "Parsed HID_ID: $HID_ID"

if [ -z "$HID_ID" ] || [ "$HID_ID" -eq 0 ]; then
    echo "Error: Invalid HID_ID parsed."
    exit 1
fi

CONFIG_FILE="/etc/g733-bpf/config"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: $CONFIG_FILE not found — run 'sudo make install' first"
    exit 1
fi
# shellcheck source=/dev/null
source "$CONFIG_FILE"
cd "$PROJECT_DIR" || { echo "Error: PROJECT_DIR='$PROJECT_DIR' not accessible"; exit 1; }

echo "Modifying g733_bpf.c with new HID_ID: $HID_ID"
sed -i -E "s/\.hid_id = [0-9]+, \/\/ Logitech G733 wireless/\.hid_id = $HID_ID, \/\/ Logitech G733 wireless/" g733_bpf.c
if ! grep -qE "\.hid_id = $HID_ID," g733_bpf.c; then
    echo "Error: failed to patch hid_id in g733_bpf.c"
    exit 1
fi

echo "Cleaning and recompiling..."
make clean
make

echo "Unregistering old struct_ops links..."
bpftool struct_ops unregister name g733_battery_ops || true
rm -rf /sys/fs/bpf/g733 /sys/fs/bpf/g733_battery_ops || true
mkdir -p /sys/fs/bpf/g733

echo "Registering new struct_ops..."
bpftool struct_ops register ./g733_bpf.bpf.o /sys/fs/bpf/g733 || { echo "Failed to load BPF"; exit 1; }

echo "Rebinding driver..."
echo "$DEV_NAME" > /sys/bus/hid/drivers/hid-generic/unbind || echo "Warning: unbind failed (may already be unbound or on a different driver)"
echo "$DEV_NAME" > /sys/bus/hid/drivers/hid-generic/bind || { echo "Error: bind failed for $DEV_NAME"; exit 1; }

# Trigger headsetcontrol to wake up power supply
if command -v headsetcontrol >/dev/null 2>&1; then
    echo "Waiting for headset to fully initialize..."
    sleep 3
    
    HC_OUT=$(headsetcontrol -b 2>&1)
    if echo "$HC_OUT" | grep -q -- "-24%"; then
        echo "Headset is physically powered off but charging. Skipping wake-up."
    else
        echo "Headset battery registered successfully."
    fi
fi

echo "Done!"
