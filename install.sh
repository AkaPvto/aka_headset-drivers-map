#!/bin/bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; BOLD='\033[1m'; NC='\033[0m'
ok()  { echo -e "${GREEN}✓${NC} $*"; }
err() { echo -e "${RED}✗${NC} $*" >&2; exit 1; }

if [ "$EUID" -ne 0 ]; then
    err "Run as root: sudo ./install.sh"
fi

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo -e "${BOLD}Installing G733 HID-BPF from:${NC} $PROJECT_DIR"
echo ""

# Dependency check
echo "Checking dependencies..."
for cmd in clang bpftool make; do
    command -v "$cmd" >/dev/null 2>&1 || err "$cmd not found — install it and re-run"
done
command -v headsetcontrol >/dev/null 2>&1 || echo "  Note: headsetcontrol not found (optional, used to wake up battery reporting)"
ok "Dependencies satisfied"

# Store project location so the loader can find sources to recompile
mkdir -p /etc/g733-bpf
echo "PROJECT_DIR=\"$PROJECT_DIR\"" > /etc/g733-bpf/config
ok "Config written to /etc/g733-bpf/config"

# Scripts
install -m 755 "$PROJECT_DIR/scripts/g733-bpf-loader.sh" /usr/local/bin/
install -m 755 "$PROJECT_DIR/scripts/g733-smart-poll.sh"  /usr/local/bin/
ok "Scripts installed to /usr/local/bin/"

# udev rule
install -m 644 "$PROJECT_DIR/scripts/99-g733-bpf.rules" /etc/udev/rules.d/
ok "udev rule installed"

# systemd service
install -m 644 "$PROJECT_DIR/scripts/g733-battery-poll.service" /etc/systemd/system/
ok "systemd service installed"

# Reload everything and enable the polling service
udevadm control --reload-rules
udevadm trigger
systemctl daemon-reload
systemctl enable --now g733-battery-poll.service
ok "Services reloaded and enabled"

# If the G733 dongle is already connected, trigger the loader now.
# udevadm trigger only fires 'change' events, not 'add', so the udev rule
# won't fire for already-present devices. We detect and activate immediately.
G733_UEVENT=$(grep -rl "HID_NAME=Logitech G733 Gaming Headset" /sys/bus/hid/devices/*/uevent 2>/dev/null | head -1)
if [ -n "$G733_UEVENT" ]; then
    G733_DEVPATH=$(readlink -f "$(dirname "$G733_UEVENT")" | sed 's|/sys||')
    echo "G733 already connected — activating BPF loader now..."
    /usr/local/bin/g733-bpf-loader.sh "$G733_DEVPATH" &
    ok "BPF loader triggered (running in background, check /var/log/g733-bpf-loader.log)"
fi

echo ""
echo -e "${BOLD}Done!${NC} G733 battery reporting will activate on next dongle connection."
