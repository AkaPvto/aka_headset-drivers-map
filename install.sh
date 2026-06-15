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

echo ""
echo -e "${BOLD}Done!${NC} Plug in your G733 headset to activate battery reporting."
