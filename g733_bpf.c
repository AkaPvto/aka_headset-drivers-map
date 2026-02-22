// SPDX-License-Identifier: GPL-2.0
/*
 * Copyright (C) 2024 Your Name <your.email@example.com>
 *
 * BPF program to expose Logitech G733 battery status to UPower via standard HID
 * Power Device reports.
 *
 * This eBPF program:
 * 1. Hooks hid_rdesc_fixup to append a standard HID Power Device descriptor to
 * the G733's report
 * 2. Hooks hid_device_event to intercept HID++ battery packets and translate
 * them to standard reports
 *
 * Reference:
 * - HID++ protocol: https://lekensteyn.nl/files/logitech/
 * - G733 calibration from headsetcontrol:
 * https://github.com/Guytp/headsetcontrol
 *
 * Loaded via: udev-hid-bpf (or manual: echo program.o >
 * /sys/kernel/config/hid_bpf/...)
 */

/* "undefine" structs and enums in vmlinux.h, because we "override" them below
 */
#define hid_bpf_ctx hid_bpf_ctx___not_used
#define hid_bpf_ops hid_bpf_ops___not_used
#define hid_report_type hid_report_type___not_used
#define hid_class_request hid_class_request___not_used
#define HID_INPUT_REPORT HID_INPUT_REPORT___not_used
#define HID_OUTPUT_REPORT HID_OUTPUT_REPORT___not_used
#define HID_FEATURE_REPORT HID_FEATURE_REPORT___not_used
#define HID_REPORT_TYPES HID_REPORT_TYPES___not_used
#define HID_REQ_GET_REPORT HID_REQ_GET_REPORT___not_used
#define HID_REQ_GET_IDLE HID_REQ_GET_IDLE___not_used
#define HID_REQ_GET_PROTOCOL HID_REQ_GET_PROTOCOL___not_used
#define HID_REQ_SET_REPORT HID_REQ_SET_REPORT___not_used
#define HID_REQ_SET_IDLE HID_REQ_SET_IDLE___not_used
#define HID_REQ_SET_PROTOCOL HID_REQ_SET_PROTOCOL___not_used

#define BPF_NO_KFUNC_PROTOTYPES

#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>

#undef hid_bpf_ctx
#undef hid_bpf_ops
#undef hid_report_type
#undef hid_class_request
#undef HID_INPUT_REPORT
#undef HID_OUTPUT_REPORT
#undef HID_FEATURE_REPORT
#undef HID_REPORT_TYPES
#undef HID_REQ_GET_REPORT
#undef HID_REQ_GET_IDLE
#undef HID_REQ_GET_PROTOCOL
#undef HID_REQ_SET_REPORT
#undef HID_REQ_SET_IDLE
#undef HID_REQ_SET_PROTOCOL

enum hid_report_type {
  HID_INPUT_REPORT = 0,
  HID_OUTPUT_REPORT = 1,
  HID_FEATURE_REPORT = 2,
  HID_REPORT_TYPES,
};

struct hid_bpf_ctx {
  struct hid_device *hid;
  __u32 allocated_size;
  union {
    __s32 retval;
    __s32 size;
  };
} __attribute__((preserve_access_index));

enum hid_class_request {
  HID_REQ_GET_REPORT = 0x01,
  HID_REQ_GET_IDLE = 0x02,
  HID_REQ_GET_PROTOCOL = 0x03,
  HID_REQ_SET_REPORT = 0x09,
  HID_REQ_SET_IDLE = 0x0A,
  HID_REQ_SET_PROTOCOL = 0x0B,
};

struct hid_bpf_ops {
  int hid_id;
  u32 flags;
  struct list_head list;
  int (*hid_device_event)(struct hid_bpf_ctx *ctx,
                          enum hid_report_type report_type, u64 source);
  int (*hid_rdesc_fixup)(struct hid_bpf_ctx *ctx);
  int (*hid_hw_request)(struct hid_bpf_ctx *ctx, unsigned char reportnum,
                        enum hid_report_type rtype,
                        enum hid_class_request reqtype, u64 source);
  int (*hid_hw_output_report)(struct hid_bpf_ctx *ctx, u64 source);
  struct hid_device *hdev;
};

extern __u8 *hid_bpf_get_data(struct hid_bpf_ctx *ctx, unsigned int offset,
                              const size_t __sz) __weak __ksym;

char __license[] SEC("license") = "GPL";

/* ============================================================================
 * HID-BPF Device Configuration
 * ============================================================================
 * Device IDs for all Logitech G733 USB variants in BTF map format.
 * This tells the HID-BPF loader which devices this program applies to.
 */
const volatile unsigned int target_hid_devices[] = {
    (0x046d << 16) | 0x0ab5, // G733 wired variant
    (0x046d << 16) | 0x0afe, // G733 wireless variant 1
    (0x046d << 16) | 0x0b1f  // G733 wireless variant 2
};

/* ============================================================================
 * HID Power Device Report Descriptor
 * ============================================================================
 * This descriptor defines a standard Power Device with:
 * - Report ID 0x50
 * - Absolute State of Charge (2 bytes: percentage + charging flag)
 * - Will be appended to G733's native descriptor
 */
static const unsigned char hid_power_device_rdesc[] = {
    0x05, 0x85,       // Usage Page (Battery System)
    0x09, 0x01,       // Usage (Smart Battery)
    0xa1, 0x01,       // Collection (Application)
    0x85, 0x50,       //   Report ID (80)
    0x05, 0x85,       //   Usage Page (Battery System)
    0x09, 0x65,       //   Usage (AbsoluteStateOfCharge)
    0x15, 0x00,       //   Logical Minimum (0%)
    0x26, 0x64, 0x00, //   Logical Maximum (100%)
    0x75, 0x08,       //   Report Size (8 bits)
    0x95, 0x01,       //   Report Count (1)
    0x81, 0x02,       //   Input (Data, Var, Abs)
    0x09, 0x44,       //   Usage (Charging)
    0x15, 0x00,       //   Logical Minimum (0)
    0x25, 0x01,       //   Logical Maximum (1)
    0x75, 0x08,       //   Report Size (8 bits)
    0x95, 0x01,       //   Report Count (1)
    0x81, 0x02,       //   Input (Data, Var, Abs)
    0xc0              // End Collection
};

/* ============================================================================
 * Battery Calibration Data for Logitech G733
 * ============================================================================
 * Voltage-to-percentage mapping based on headsetcontrol's LOGITECH_G633
 * calibration (G733 uses identical calibration).
 *
 * These are 8-point calibration curves for Li-Ion battery discharge.
 * Format: (voltage_mV, percentage) pairs
 */
static const int g733_voltages[] = {
    4100, // 100%
    3950, // 80%
    3850, // 60%
    3750, // 40%
    3650, // 20%
    3500, // 10%
    3300, // 5%
    3150  // 0%
};

static const int g733_percentages[] = {100, 80, 60, 40, 20, 10, 5, 0};

/* ============================================================================
 * Linear Interpolation: voltage -> percentage
 * ============================================================================
 * Given a measured voltage, estimate battery percentage using linear
 * interpolation between calibration points.
 *
 * @param voltage Measured voltage in mV
 * @return Battery percentage (0-100%)
 */
static int get_battery_percentage(int voltage) {
  const unsigned int num_points = 8U;

  // Clamp to known range
  if (voltage >= g733_voltages[0])
    return 100;
  if (voltage <= g733_voltages[num_points - 1])
    return 0;

// Linear interpolation
#pragma unroll
  for (unsigned int i = 0U; i < num_points - 1U; i++) {
    int v_high = g733_voltages[i];
    int v_low = g733_voltages[i + 1U];

    // Check if voltage falls in this segment [v_low, v_high]
    if (voltage >= v_low && voltage <= v_high) {
      unsigned int v_range = (unsigned int)(v_high - v_low);
      if (v_range == 0U)
        return g733_percentages[i];

      int p_high = g733_percentages[i];
      int p_low = g733_percentages[i + 1U];
      unsigned int p_range = (unsigned int)(p_high - p_low);
      unsigned int v_offset = (unsigned int)(voltage - v_low);

      // percentage = p_low + (v_offset / v_range) * p_range (using unsigned
      // div)
      int percentage = p_low + (int)((v_offset * p_range) / v_range);
      return percentage;
    }
  }

  return 0;
}

/* ============================================================================
 * HID Report Descriptor Fixup
 * ============================================================================
 * Appends a standard HID Power Device descriptor to the G733's native
 * report descriptor. This makes the kernel recognize it as a battery device.
 *
 * Modern API: Takes context struct (marked as BTF type-tagged for kfunc),
 * uses hid_bpf_get_data() to safely access the descriptor buffer.
 */
SEC("struct_ops/hid_rdesc_fixup")
int BPF_PROG(g733_fix_rdesc, struct hid_bpf_ctx *hctx) {
  // Get a bounded, verifier-approved pointer to the descriptor
  // HID_MAX_DESCRIPTOR_SIZE is 4096 bytes
  __u8 *data = (__u8 *)hid_bpf_get_data(hctx, 0, 4096);
  if (!data)
    return 0;

  // Get current descriptor size from context
  __u32 current_size = hctx->size;

  // Check if there's enough space to append our descriptor
  if (current_size + sizeof(hid_power_device_rdesc) > 4096)
    return 0;

  // Append the Power Device descriptor to the end
  __u32 offset = current_size;
  for (unsigned int i = 0; i < sizeof(hid_power_device_rdesc); i++) {
    data[offset + i] = hid_power_device_rdesc[i];
  }

  // Return the new total size
  return current_size + sizeof(hid_power_device_rdesc);
}

/* ============================================================================
 * HID Device Event Interceptor
 * ============================================================================
 * Intercepts incoming HID reports from the G733 and translates HID++ battery
 * reports into standard Power Device reports.
 *
 * Modern API: Takes context, report type, and source flags. Uses
 * hid_bpf_get_data() to safely access the live packet buffer.
 *
 * HID++ Long Packet Structure (20 bytes):
 *   [0]    = 0x11 (HIDPP_LONG_MESSAGE identifier)
 *   [1]    = Device index
 *   [2-3]  = Feature/SubID (0x08, 0x0a for battery on G733)
 *   [4-5]  = Voltage (big-endian, in mV)
 *   [6]    = Charging status (0x01=idle, 0x03=charging)
 *   [7-19] = Unused/padding
 *
 * Standard Power Device Report (3 bytes):
 *   [0]    = 0x50 (Report ID)
 *   [1]    = Battery percentage (0-100)
 *   [2]    = Charging status (0x00=discharging, 0x01=charging)
 */
SEC("struct_ops/hid_device_event")
int BPF_PROG(g733_device_event, struct hid_bpf_ctx *hctx,
             enum hid_report_type type, __u64 source) {
  // Get a bounded pointer to the packet data (assume max 64 bytes)
  __u8 *data = (__u8 *)hid_bpf_get_data(hctx, 0, 64);
  if (!data)
    return 0;

  // Validate packet is HID++ long message (20 bytes) from battery feature
  if (hctx->size < 20)
    return 0;

  if (data[0] != 0x11U) // Not a HID++ long message
    return 0;

  // Feature check: 0x08, 0x0a is battery voltage feature on G733
  if (data[2] != 0x08U || data[3] != 0x0aU)
    return 0;

  // Extract raw voltage (bytes [4-5], big-endian)
  __u32 voltage = ((__u32)data[4] << 8) | ((__u32)data[5]);

  // Extract charging status (byte [6]: 0x01 = idle, 0x03 = charging)
  __u32 charging_raw = data[6];
  __u32 charging = (charging_raw == 0x03U) ? 1U : 0U;

  // Convert voltage to percentage
  int percentage = get_battery_percentage((int)voltage);

  bpf_printk("G733 battery: voltage=%umV, charging=%u, percentage=%d%%\n",
             voltage, charging, percentage);

  // Transform packet into standard Power Device report
  data[0] = 0x50U;            // Report ID: Power Device
  data[1] = (__u8)percentage; // Battery percentage (0-100)
  data[2] = (__u8)charging;   // Charging flag (0 or 1)

  // Return the new packet size (3 bytes: report_id + percent + charging flag)
  return 3;
}

/* ============================================================================
 * Bind BPF Programs to Kernel HID-BPF Operations
 * ============================================================================
 * This .struct_ops.link section registers your BPF functions with the
 * kernel's HID subsystem. Modern libbpf automatically handles BTF mapping.
 */
SEC(".struct_ops.link")
struct hid_bpf_ops g733_battery_ops = {
    .hid_id = 8, // Logitech G733 wireless (add more
                 // variants via separate instances)
    .hid_rdesc_fixup = (void *)g733_fix_rdesc,
    .hid_device_event = (void *)g733_device_event,
};
