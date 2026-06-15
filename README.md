# Logitech G733 HID-BPF Integration

Exposes the battery percentage of the Logitech G733 Wireless Gaming Headset to the Linux UPower subsystem using an eBPF (`struct_ops`) program — so the battery shows up in your system tray and desktop widgets like any other device.

## How it works

The project intercepts wireless headset communication right above the Linux HID subsystem using `hid-bpf`. When the headset connects, a `udev` rule captures its dynamic sysfs `hid_id`, recompiles the BPF program with that ID via `make`, and registers it with the kernel using `bpftool`. A background `systemd` service smartly polls the headset for battery updates.

The injected BPF hooks do two things:
1. **`hid_rdesc_fixup`** — appends a standard HID Power Device descriptor (Battery System 0x85, Report ID 0x50) to the G733's native descriptor, making the kernel spawn a UPower power supply.
2. **`hid_device_event`** — intercepts HID++ battery voltage packets, converts them to a percentage via a calibrated voltage curve, and emits a standard Power Device report.

## Files

| File | Purpose |
|---|---|
| `g733_bpf.c` | BPF program: descriptor fixup + event interception |
| `Makefile` | Build, test, install, and clean targets |
| `install.sh` / `uninstall.sh` | One-command setup and teardown |
| `scripts/g733-bpf-loader.sh` | Triggered by udev: recompiles and registers the BPF program |
| `scripts/g733-smart-poll.sh` | Background loop: pings the headset and adjusts poll rate |
| `scripts/99-g733-bpf.rules` | udev rule: fires the loader when the headset connects |
| `scripts/g733-battery-poll.service` | systemd service: runs the smart poller |
| `tests/` | Unit tests (C + bash, no kernel or hardware needed) |

## Dependencies

```
clang      bpftool      make      headsetcontrol (optional but recommended)
```

`headsetcontrol` is used to trigger the headset to emit a battery packet so the BPF program can intercept it. Without it, battery data is only reported when the headset sends packets spontaneously (e.g., on cable connect/disconnect events).

## Installation

```bash
git clone <repo-url>
cd headset_drivers_map
sudo make install
```

That's it. Plug in your G733 and battery reporting activates automatically.

To remove everything:

```bash
sudo make uninstall
```

> **Note:** The installer records the repo path so the loader can recompile on each plug-in event. If you move the directory, just re-run `sudo make install`.

## Testing

Unit tests cover the voltage→percentage math, the HID_ID parsing in the loader, and the smart polling logic. No root access, BPF support, or hardware needed.

```bash
make test
```

## Smart polling

The background service adjusts how often it pings the headset based on the current battery state:

| Condition | Poll interval |
|---|---|
| Battery ≥ 95% **and** charging | 15 s — catch the moment it finishes |
| Battery ≤ 5% **and** discharging | 15 s — catch the moment it dies |
| Everything else | 5 min |
