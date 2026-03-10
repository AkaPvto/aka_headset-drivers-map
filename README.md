# Logitech G733 HID-BPF Integration

This project contains an eBPF (`struct_ops`) program that natively exposes the battery percentage of the Logitech G733 Wireless Gaming Headset to the Linux UPower subsystem, enabling desktop integration (like the battery showing in the system tray).

## Architecture

The project intercepts wireless headset communication right above the Linux HID subsystem using `hid-bpf`.
When the kernel identifies the headset, a `udev` rule parses the headset's dynamic Sysfs `hid_id`. A background `systemd` worker dynamically edits `g733_bpf.c` with this ID, compiles it via `make`, and links it directly into the kernel using `bpftool`. 

The injected BPF hooks intercepts the headset's HID descriptor parsing and appends a `Battery System` (0x85) payload with the `AbsoluteStateOfCharge` (0x65) mapping, forcing the desktop to spawn a Linux Power Supply class.

## Files

1. `g733_bpf.c` -> The core BPF source code hooks that intercept HID packets, parse Logitech wireless voltage events, and convert them to standard UPower percentages.
2. `Makefile` -> A small C-build tool that uses `clang` to compile `g733_bpf.c` into a binary kernel payload (`g733_bpf.bpf.o`) wrapped against the system's `vmlinux.h`.

*(For the active background loader scripts, please see `./scripts/g733-bpf-loader.sh` and `./scripts/99-g733-bpf.rules`. They orchestrate this repository contents).*

## Automation Setup

To make the HID-BPF program reload automatically every time the headset connects or the PC restarts, we use a `udev` rule and a bash loader script provided in the `./scripts` folder.

To install the automation, run the following commands:

```bash
# 1. Copy the loader script to /usr/local/bin and make it executable
sudo cp ./scripts/g733-bpf-loader.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/g733-bpf-loader.sh

# 2. Copy the udev rule to /etc/udev/rules.d/
sudo cp ./scripts/99-g733-bpf.rules /etc/udev/rules.d/

# 3. Copy the smart background polling service to keep battery updated
sudo cp ./scripts/g733-smart-poll.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/g733-smart-poll.sh
sudo cp ./scripts/g733-battery-poll.service /etc/systemd/system/

# 4. Reload demons and activate
sudo udevadm control --reload-rules
sudo udevadm trigger
sudo systemctl daemon-reload
sudo systemctl enable --now g733-battery-poll.service
```

Once installed:
- `udev` will detect the dynamically assigned `hid_id` of the headset, automatically adjust `g733_bpf.c`, recompile, and register the BPF object transparently.
- The `g733-battery-poll` systemd background service will smartly ping the headset based on its battery state. If the battery is under 5% AND discharging, or over 95% AND charging, it polls every 15 seconds so you know exactly when it finishes or dies. Otherwise, it polls every 5 minutes safely in the background.