#!/usr/bin/env bash
#
# cec_check.sh
# Simple interactive script to test HDMI-CEC commands on a Raspberry Pi.
#

# Make sure cec-client is installed
if ! command -v cec-client &> /dev/null
then
    echo "cec-client not found. Install with: sudo apt-get install cec-utils"
    exit 1
fi

echo "========================================"
echo " HDMI-CEC Device Check & Test Script"
echo "========================================"

echo ""
echo "Detecting available CEC adapters and devices..."
echo ""
# The -l option lists the available CEC adapters on your system.
# For many Raspberry Pi setups, you'll see one adapter like 'RPI'.
cec-client -l
echo ""
echo "If you see something like 'com ports' or 'RPI' listed, that means your Pi's CEC adapter is detected."
echo ""

read -rp "Press ENTER to start scanning for connected CEC devices..."
echo "Scanning for devices..."
echo "--------------------------------"

# The 'scan' command tries to detect all devices on the CEC bus
scan_output=$(echo "scan" | cec-client -s -d 1 2>/dev/null)

# Show output to the user
echo "${scan_output}"
echo "--------------------------------"
echo ""
echo "Above is the raw device scan. Typical device addresses are 0 (TV), 1 (Recording Device), 2 (Tuner), 3 (Playback), etc."
echo "Find the 'logical address' of the device you want to test (0, 1, 2, 3...)."
echo ""

# Prompt user for address
read -rp "Enter the device address (e.g. 0 for TV): " device_addr

# Quick check: if user didn't type anything, default to 0 (TV)
if [[ -z "$device_addr" ]]; then
    device_addr="0"
fi

echo ""
echo "Okay, we will run three tests on device address '${device_addr}'."
echo "1) Turn screen off (standby)"
echo "2) Turn screen on"
echo "3) Change input source to the Pi"
echo ""
read -rp "Press ENTER to begin Test #1 (screen off)..."

# Test 1: Turn screen off
echo ""
echo "Sending standby command to device #${device_addr}..."
echo "standby ${device_addr}" | cec-client -s -d 1
echo ""
read -rp "Did the screen turn off successfully? (Press ENTER to continue)"

# Test 2: Turn screen on
echo ""
read -rp "Press ENTER to begin Test #2 (screen on)..."
echo ""
echo "Sending 'on' command to device #${device_addr}..."
echo "on ${device_addr}" | cec-client -s -d 1
echo ""
read -rp "Did the screen turn on successfully? (Press ENTER to continue)"

# Test 3: Change active source
echo ""
read -rp "Press ENTER to begin Test #3 (change active source)..."
echo ""
echo "Sending 'as' (active source) command. Usually you send 'as' to the Pi's logical address, which might be 1, 2, or 3, depending on the Pi's role."
echo "We'll try 'as' from the Pi itself. If Pi is device #1, we'll do 'tx 1F:82:10:00', etc."
echo ""

# If the Pi’s logical address is different from your target device, you can refine these commands.
# For a quick test, "as" attempts to set the Pi as the active source, so the TV should switch input.
echo "as" | cec-client -s -d 1

echo ""
echo "If the TV/monitor source changed to your Pi automatically, that means it worked!"
echo ""
echo "=============== TEST COMPLETE ==============="
echo "If something didn't work, double check your device address and ensure your TV supports CEC."
echo "Consult cec-client docs for advanced usage."
