#!/bin/bash
# Unit tests for the smart polling logic in g733-smart-poll.sh.
# Tests UPower output parsing and sleep-interval decisions in isolation
# (no real UPower or headsetcontrol needed).

failures=0

pass() { printf "  PASS  %s\n" "$1"; }
fail() { printf "  FAIL  %s — %s\n" "$1" "$2"; (( failures++ )) || true; }

# ---------------------------------------------------------------------------
# UPower output parsing
# Mirrors the awk commands in g733-smart-poll.sh lines 20-21.
# ---------------------------------------------------------------------------
parse_upower_output() {
    local mock="$1"
    PERCENTAGE=$(echo "$mock" | awk '/headset/ {p=1} p && /percentage/ {print $2; exit}' | tr -d '%')
    ICON=$(echo "$mock"       | awk '/headset/ {p=1} p && /icon-name/  {print $2; exit}' | tr -d "'")
}

UPOWER_CHARGING="
/org/freedesktop/UPower/devices/headset_dev_046D_0B1F
  type:              headset
  percentage:        97%
  icon-name:        'battery-full-charging'
"

UPOWER_DISCHARGING="
/org/freedesktop/UPower/devices/headset_dev_046D_0B1F
  type:              headset
  percentage:        3%
  icon-name:        'battery-caution'
"

UPOWER_NORMAL="
/org/freedesktop/UPower/devices/headset_dev_046D_0B1F
  type:              headset
  percentage:        50%
  icon-name:        'battery-good'
"

UPOWER_NO_HEADSET="
/org/freedesktop/UPower/devices/DisplayDevice
  type:              unknown
  percentage:        0%
  icon-name:        'battery-missing'
"

echo "=== UPower output parsing ==="
echo ""

parse_upower_output "$UPOWER_CHARGING"
[[ "$PERCENTAGE" == "97" ]]      && pass "charging: percentage=97"              || fail "charging: percentage"     "got '$PERCENTAGE'"
echo "$ICON" | grep -q "charging" && pass "charging: icon contains 'charging'" || fail "charging: icon"            "got '$ICON'"

parse_upower_output "$UPOWER_DISCHARGING"
[[ "$PERCENTAGE" == "3" ]]       && pass "discharging: percentage=3"                      || fail "discharging: percentage" "got '$PERCENTAGE'"
echo "$ICON" | grep -qv "charging" && pass "discharging: icon does not contain 'charging'" || fail "discharging: icon"      "got '$ICON'"

parse_upower_output "$UPOWER_NORMAL"
[[ "$PERCENTAGE" == "50" ]] && pass "normal: percentage=50" || fail "normal: percentage" "got '$PERCENTAGE'"

parse_upower_output "$UPOWER_NO_HEADSET"
[[ -z "$PERCENTAGE" ]] && pass "no headset: percentage is empty" || fail "no headset: percentage should be empty" "got '$PERCENTAGE'"

echo ""

# ---------------------------------------------------------------------------
# Sleep-interval decision logic
# Mirrors the if/elif chain in g733-smart-poll.sh lines 27-36.
# ---------------------------------------------------------------------------
decide_sleep() {
    local pct="$1" icon="$2"
    if [ -z "$pct" ]; then
        echo 300
    elif [ "$pct" -ge 95 ] && echo "$icon" | grep -q "charging"; then
        echo 15
    elif [ "$pct" -le 5 ] && ! echo "$icon" | grep -q "charging"; then
        echo 15
    else
        echo 300
    fi
}

echo "=== Polling interval decisions ==="
echo ""

check_sleep() {
    local name="$1" pct="$2" icon="$3" expected="$4"
    local result
    result=$(decide_sleep "$pct" "$icon")
    [[ "$result" -eq "$expected" ]] \
        && pass "$name" \
        || fail "$name" "expected ${expected}s, got ${result}s"
}

# Fast-poll cases
check_sleep "97% + charging           → 15s"  "97"  "battery-full-charging"   15
check_sleep "95% + charging (edge)    → 15s"  "95"  "battery-full-charging"   15
check_sleep "100% + charging          → 15s"  "100" "battery-full-charging"   15
check_sleep "3% discharging           → 15s"  "3"   "battery-caution"         15
check_sleep "5% discharging (edge)    → 15s"  "5"   "battery-caution"         15

# Normal-poll cases
check_sleep "50% normal               → 300s" "50"  "battery-good"            300
check_sleep "no headset               → 300s" ""    ""                        300
check_sleep "3% but charging          → 300s" "3"   "battery-caution-charging" 300
check_sleep "97% not charging         → 300s" "97"  "battery-full"            300
check_sleep "96% charging (below 95+) → 300s" "6"  "battery-charging"        300
check_sleep "4% charging (not crit)   → 300s" "4"   "battery-caution-charging" 300
check_sleep "94% not critical         → 300s" "94"  "battery-good"            300

echo ""
printf "%s — %d failure(s)\n" \
    "$( (( failures == 0 )) && echo 'ALL PASSED' || echo 'FAILED' )" \
    "$failures"
exit "$(( failures > 0 ? 1 : 0 ))"
