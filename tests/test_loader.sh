#!/bin/bash
# Unit tests for the loader script's HID_ID parsing and sed substitution logic.

failures=0

pass() { printf "  PASS  %s\n" "$1"; }
fail() { printf "  FAIL  %s — %s\n" "$1" "$2"; (( failures++ )) || true; }

# ---------------------------------------------------------------------------
# HID_ID extraction (mirrors logic in g733-bpf-loader.sh)
# DEVPATH looks like: /devices/pci0000:00/.../0003:046D:0B1F.0004
# We take the basename, cut on '.', and parse the hex suffix as decimal.
# ---------------------------------------------------------------------------
parse_hid_id() {
    local devpath="$1"
    local dev_name hid_hex
    dev_name=$(basename "$devpath")
    hid_hex=$(echo "$dev_name" | cut -d'.' -f2)
    echo "$(( 16#$hid_hex ))"
}

test_hid_id() {
    local name="$1" devpath="$2" expected="$3"
    local result
    result=$(parse_hid_id "$devpath")
    if [[ "$result" -eq "$expected" ]]; then
        pass "$name"
    else
        fail "$name" "expected $expected, got $result"
    fi
}

echo "=== HID_ID parsing ==="
echo ""
test_hid_id "standard numeric suffix"       "/devices/pci0000:00/0003:046D:0B1F.0004"   4
test_hid_id "hex letter in suffix"           "/devices/pci0000:00/0003:046D:0B1F.000a"   10
test_hid_id "max single-byte id"             "/devices/pci0000:00/0003:046D:0B1F.00ff"   255
test_hid_id "id of 1"                        "/devices/pci0000:00/0003:046D:0B1F.0001"   1
test_hid_id "multi-level pci path"           "/devices/pci0000:00/0000:00:14.0/usb1/1-3/0003:046D:0B1F.0010"   16
test_hid_id "uppercase hex letters"          "/devices/pci0000:00/0003:046D:0B1F.00AB"   171

echo ""

# ---------------------------------------------------------------------------
# sed substitution pattern (mirrors g733-bpf-loader.sh line 34)
# ---------------------------------------------------------------------------
apply_sed() {
    local input="$1" new_id="$2"
    echo "$input" | sed -E \
        "s/\.hid_id = [0-9]+, \/\/ Logitech G733 wireless/\.hid_id = $new_id, \/\/ Logitech G733 wireless/"
}

test_sed() {
    local name="$1" input="$2" new_id="$3" expected="$4"
    local result
    result=$(apply_sed "$input" "$new_id")
    if [[ "$result" == "$expected" ]]; then
        pass "$name"
    else
        fail "$name" "expected '$expected', got '$result'"
    fi
}

echo "=== sed hid_id substitution ==="
echo ""
test_sed "id=1 → id=4" \
    "    .hid_id = 1, // Logitech G733 wireless (add more" \
    "4" \
    "    .hid_id = 4, // Logitech G733 wireless (add more"

test_sed "id=99 → id=16" \
    "    .hid_id = 99, // Logitech G733 wireless (add more" \
    "16" \
    "    .hid_id = 16, // Logitech G733 wireless (add more"

test_sed "id=255 → id=10" \
    "    .hid_id = 255, // Logitech G733 wireless (add more" \
    "10" \
    "    .hid_id = 10, // Logitech G733 wireless (add more"

test_sed "trailing text preserved" \
    "    .hid_id = 1, // Logitech G733 wireless (add more" \
    "7" \
    "    .hid_id = 7, // Logitech G733 wireless (add more"

# Verify the verification grep also works (mirrors the grep after sed)
echo ""
echo "=== post-sed verification grep ==="
echo ""

test_verify_grep() {
    local name="$1" text="$2" hid_id="$3" should_match="$4"
    if echo "$text" | grep -qE "\.hid_id = $hid_id,"; then
        matched=true
    else
        matched=false
    fi
    if [[ "$matched" == "$should_match" ]]; then
        pass "$name"
    else
        fail "$name" "match=$matched, expected $should_match"
    fi
}

test_verify_grep "grep finds correct id after patch" \
    "    .hid_id = 4, // Logitech G733 wireless (add more" "4" "true"

test_verify_grep "grep rejects wrong id" \
    "    .hid_id = 1, // Logitech G733 wireless (add more" "4" "false"

test_verify_grep "grep finds multi-digit id" \
    "    .hid_id = 16, // Logitech G733 wireless (add more" "16" "true"

echo ""
printf "%s — %d failure(s)\n" \
    "$( (( failures == 0 )) && echo 'ALL PASSED' || echo 'FAILED' )" \
    "$failures"
exit "$(( failures > 0 ? 1 : 0 ))"
