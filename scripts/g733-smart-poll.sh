#!/bin/bash
# Smart Battery Polling for Logitech G733
# Dynamically adjusts polling interval based on battery level.

while true; do
    # 1. Trigger the headset to reply with a battery packet
    headsetcontrol -b >/dev/null 2>&1
    
    # 2. Give the BPF kernel program and UPower a moment to process the reply
    sleep 2
    
    # 3. Read the exact percentage from the UPower system
    PERCENTAGE=$(upower -d | awk '/headset/ {p=1} p && /percentage/ {print $2; exit}' | tr -d '%')
    
    # 4. Decide how long to sleep until the next poll
    if [ -z "$PERCENTAGE" ]; then
        # If headset is off or disconnected, sleep for 5 minutes
        sleep 300
    elif [ "$PERCENTAGE" -le 5 ] || [ "$PERCENTAGE" -ge 95 ]; then
        # If battery is critically low or almost full, poll every 15 seconds
        sleep 15
    else
        # If battery is in normal range, poll every 5 minutes (300 seconds)
        sleep 300
    fi
done
