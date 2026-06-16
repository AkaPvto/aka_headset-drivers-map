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

CONFIG_FILE="/etc/g733-bpf/config"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: $CONFIG_FILE not found — run 'sudo make install' first"
    exit 1
fi
# shellcheck source=/dev/null
source "$CONFIG_FILE"
cd "$PROJECT_DIR" || { echo "Error: PROJECT_DIR='$PROJECT_DIR' not accessible"; exit 1; }

# Unregister any existing struct_ops FIRST, before we compile.
# This may trigger a HID re-enumeration (device gets a new sysfs ID),
# so we must detect the live device ID *after* this step.
echo "Unregistering old struct_ops links..."
bpftool struct_ops unregister name g733_battery_ops 2>/dev/null || true
rm -rf /sys/fs/bpf/g733 /sys/fs/bpf/g733_battery_ops 2>/dev/null || true

# Give the kernel a moment to finish re-enumerating if it needs to
sleep 1

# Detect the live device ID now that any re-enumeration has settled
LIVE_DEV_PATH=$(grep -rl "HID_NAME=Logitech G733 Gaming Headset" /sys/bus/hid/devices/*/uevent 2>/dev/null \
    | head -1 | xargs dirname 2>/dev/null)
if [ -z "$LIVE_DEV_PATH" ]; then
    echo "Error: G733 not found in sysfs after unregister step"
    exit 1
fi
DEV_NAME=$(basename "$LIVE_DEV_PATH")
HID_HEX=$(echo "$DEV_NAME" | cut -d'.' -f2)
HID_ID=$((16#$HID_HEX))
echo "Live device: $DEV_NAME → HID_ID: $HID_ID"

if [ -z "$HID_ID" ] || [ "$HID_ID" -eq 0 ]; then
    echo "Error: Invalid HID_ID detected."
    exit 1
fi

echo "Patching g733_bpf.c with HID_ID: $HID_ID"
sed -i -E "s/\.hid_id = [0-9]+, \/\/ Logitech G733 wireless/\.hid_id = $HID_ID, \/\/ Logitech G733 wireless/" g733_bpf.c
if ! grep -qE "\.hid_id = $HID_ID," g733_bpf.c; then
    echo "Error: failed to patch hid_id in g733_bpf.c"
    exit 1
fi

echo "Cleaning and recompiling..."
make clean
make

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
