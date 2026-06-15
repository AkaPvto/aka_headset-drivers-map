#!/bin/bash
# Run all project tests. Exit code 0 = all passed.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failures=0

run_suite() {
    local name="$1" cmd="$2"
    echo ""
    echo "--- $name ---"
    if eval "$cmd"; then
        return 0
    else
        (( failures++ )) || true
    fi
}

# C: battery percentage math
BINARY="$TESTS_DIR/test_battery"
cc -O2 -Wall -o "$BINARY" "$TESTS_DIR/test_battery.c" \
    || { echo "FAIL: could not compile test_battery.c"; (( failures++ )) || true; BINARY=""; }
[ -n "$BINARY" ] && run_suite "C: battery percentage" "$BINARY"

# Shell: loader parsing and sed
run_suite "Shell: loader" "bash $TESTS_DIR/test_loader.sh"

# Shell: smart poll logic
run_suite "Shell: smart poll" "bash $TESTS_DIR/test_poll.sh"

echo ""
echo "=============================="
if (( failures == 0 )); then
    echo "ALL TESTS PASSED"
else
    echo "FAILED: $failures suite(s) had failures"
fi
echo "=============================="
exit "$(( failures > 0 ? 1 : 0 ))"
