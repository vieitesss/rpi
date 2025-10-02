#!/bin/bash

# Check if ethernet has a carrier (cable connected)
if cat /sys/class/net/eth0/carrier 2>/dev/null | grep -q 1; then
    # Ethernet is connected, disable WiFi
    if ip link show wlan0 | grep -q "state UP"; then
        logger "Ethernet connected - disabling WiFi"
        ip link set wlan0 down
    fi
else
    # Ethernet is disconnected, enable WiFi
    if ip link show wlan0 | grep -q "state DOWN"; then
        logger "Ethernet disconnected - enabling WiFi"
        ip link set wlan0 up
    fi
fi
