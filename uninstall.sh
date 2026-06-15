#!/bin/bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Run as root: sudo ./uninstall.sh" >&2; exit 1
fi

echo "Removing G733 HID-BPF..."

systemctl disable --now g733-battery-poll.service 2>/dev/null || true

rm -f  /etc/systemd/system/g733-battery-poll.service
rm -f  /etc/udev/rules.d/99-g733-bpf.rules
rm -f  /usr/local/bin/g733-bpf-loader.sh
rm -f  /usr/local/bin/g733-smart-poll.sh
rm -rf /etc/g733-bpf

# Unload BPF program if currently active
bpftool struct_ops unregister name g733_battery_ops 2>/dev/null || true
rm -rf /sys/fs/bpf/g733 2>/dev/null || true

udevadm control --reload-rules
systemctl daemon-reload

echo "✓ Uninstalled"
