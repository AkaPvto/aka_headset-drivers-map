#!/bin/bash
# Smart Battery Polling for Logitech G733
# Dynamically adjusts polling interval based on battery level.

while true; do
    # 1. Trigger the headset to reply with a battery packet and capture its raw terminal output
    HC_OUT=$(headsetcontrol -b 2>&1)
    
    # Check if headsetcontrol reported the notorious "-24%" (meaning headset is physically OFF but charging)
    if echo "$HC_OUT" | grep -q -- "-24%"; then
        # Headset is off. Sleeping for 5 minutes instead of waking up the BPF interceptor.
        sleep 300
        continue
    fi
    
    # 2. Give the BPF kernel program and UPower a moment to process the reply
    sleep 2
    
    # 3. Read the exact percentage and state from the UPower system
    PERCENTAGE=$(upower -d | awk '/headset/ {p=1} p && /percentage/ {print $2; exit}' | tr -d '%')
    ICON=$(upower -d | awk '/headset/ {p=1} p && /icon-name/ {print $2; exit}' | tr -d "'")
    
    # 4. Decide how long to sleep until the next poll
    if [ -z "$PERCENTAGE" ]; then
        # If headset is off or disconnected, sleep for 5 minutes
        sleep 300
    elif [ "$PERCENTAGE" -ge 95 ] && echo "$ICON" | grep -q "charging"; then
        # If battery is almost full AND charging, poll every 15 seconds
        sleep 15
    elif [ "$PERCENTAGE" -le 5 ] && ! echo "$ICON" | grep -q "charging"; then
        # If battery is critically low AND discharging, poll every 15 seconds
        sleep 15
    else
        # If battery is in normal range or not actively critical, poll every 5 minutes (300 seconds)
        sleep 300
    fi
done
