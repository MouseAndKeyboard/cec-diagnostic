#!/usr/bin/env bash
#
# cec_wizard.sh
# Interactive script to pick a device and confirm which CEC commands work.
#
# Make executable with:
#   chmod +x cec_wizard.sh
#

CONFIG_FILE="cec_config.json"

###############################################################################
# Helper functions
###############################################################################

function require_cec_client() {
  if ! command -v cec-client &> /dev/null; then
    echo "Error: cec-client not found (cec-utils not installed?)."
    echo "Install with: sudo apt-get update && sudo apt-get install cec-utils"
    exit 1
  fi
}

function minimal_scan() {
  # We use -d 8 for minimal debug messages (0=none, 1=error, 2=warning, 3=notice, 4=info, 5=debug, 8=trace)
  # But often 1 or 2 is enough to suppress spam. Try adjusting as needed.
  echo "scan" | cec-client -s -d 8 $CEC_ADAPTER 2>/dev/null
}

function run_cec_command() {
  local cmd="$1"
  echo "$cmd" | cec-client -s -d 8 $CEC_ADAPTER 2>/dev/null
}

function prompt_yes_no() {
  local prompt="$1 (y/n)? "
  local choice
  while true; do
    read -r -p "$prompt" choice
    case "$choice" in
      [Yy]* ) return 0 ;;
      [Nn]* ) return 1 ;;
      * ) echo "Please type y or n." ;;
    esac
  done
}

function save_config() {
  local device_addr="$1"
  local off_cmd="$2"
  local on_cmd="$3"
  local source_cmd="$4"

  cat > "$CONFIG_FILE" <<EOF
{
  "device_address": "${device_addr}",
  "power_off_cmd": "${off_cmd}",
  "power_on_cmd": "${on_cmd}",
  "switch_source_cmd": "${source_cmd}"
}
EOF
  echo "Configuration saved to $CONFIG_FILE."
}

###############################################################################
# Main Wizard Logic
###############################################################################

require_cec_client

echo "========================================"
echo "CEC Configuration Wizard"
echo "========================================"
echo ""

# If you have multiple adapters (e.g., /dev/cec0, /dev/cec1), set CEC_ADAPTER here:
#   e.g., CEC_ADAPTER="/dev/cec1"
# Otherwise, leave blank to let cec-client pick the default.
CEC_ADAPTER=""

echo "Running device scan. Please wait..."
echo "----------------------------------------"
scan_result=$(minimal_scan)
echo "$scan_result"
echo "----------------------------------------"
echo ""
echo "Look above for detected devices. Each device typically has a 'Logical address': 0 (TV), 1, 2, 3, etc."
echo ""

read -rp "Enter the device address you want to control (default 0): " device_addr
if [[ -z "$device_addr" ]]; then
  device_addr="0"
fi

echo ""
echo "Great. We'll attempt to control device address '$device_addr'."
echo "We'll test three actions: Power Off, Power On, and Switch Source."
echo ""

###############################################################################
# 1) Test Power Off
###############################################################################
echo "Test #1: Power Off"
echo "We'll try two approaches, in case your TV requires a specific hex code."
echo ""

power_off_cmd="standby $device_addr"
echo "Attempting: $power_off_cmd"
run_cec_command "$power_off_cmd"

if prompt_yes_no "Did the TV (device $device_addr) actually turn off"; then
  echo "Good! We will store '$power_off_cmd' as the working power-off command."
else
  echo "Okay, let's try sending hex directly for 'standby'."
  # Example: for 'device 1 -> device 0' it's '10:36'
  # But if user says $device_addr is '0', we typically send from Pi's address to 0.
  # Let's guess the Pi is address '1' for demonstration. Adjust as needed.
  # This is purely an example. If your Pi is address 4 -> device_addr=0 => '40:36', etc.
  # We'll do a small guess: FROM=1 TO=$device_addr => "1${device_addr}:36"
  # We'll do a sanity check that $device_addr is a single digit or so. 
  # If $device_addr is single-digit, that’s okay. Otherwise, might need parsing.
  hex_from="1"
  hex_msg="${hex_from}${device_addr}:36"
  power_off_cmd="tx $hex_msg"

  echo "Attempting: $power_off_cmd"
  run_cec_command "$power_off_cmd"

  if prompt_yes_no "Did the TV turn off now"; then
    echo "We'll store '$power_off_cmd' as the working power-off command."
  else
    echo "It appears neither method worked. We'll store a null command for off."
    power_off_cmd=""
  fi
fi

echo ""
echo "Done with Power Off test."
echo ""

###############################################################################
# 2) Test Power On
###############################################################################
echo "Test #2: Power On"
echo "We'll again try a standard approach first: 'on <addr>'."
echo ""

power_on_cmd="on $device_addr"
echo "Attempting: $power_on_cmd"
run_cec_command "$power_on_cmd"

if prompt_yes_no "Did the TV (device $device_addr) power on"; then
  echo "Great, storing '$power_on_cmd' as the working power-on command."
else
  echo "We'll try a hex approach. Typically 'tx 10:04' or 'tx 40:04', etc. (opcode 0x04 = Image View On)."
  # We'll guess Pi = address 1, target = device_addr. 
  # Format: "1<device_addr>:04"
  hex_from="1"
  hex_msg="${hex_from}${device_addr}:04"
  power_on_cmd="tx $hex_msg"

  echo "Attempting: $power_on_cmd"
  run_cec_command "$power_on_cmd"

  if prompt_yes_no "Did the TV power on now"; then
    echo "Storing '$power_on_cmd' as the working power-on command."
  else
    echo "No success with either method. We'll store no command for on."
    power_on_cmd=""
  fi
fi

echo ""
echo "Done with Power On test."
echo ""

###############################################################################
# 3) Test Switch Source
###############################################################################
echo "Test #3: Switch Source"
echo "We'll try 'as' (Active Source) first."
echo ""

switch_source_cmd="as"
echo "Attempting: $switch_source_cmd"
run_cec_command "$switch_source_cmd"

if prompt_yes_no "Did the TV switch input to the Pi"; then
  echo "Storing '$switch_source_cmd' as the working switch-source command."
else
  echo "We'll try another approach. Often 'tx 1F:82:10:00' or similar can force switch to a specific physical address."
  # This is more complicated—physical address depends on your Pi’s HDMI port, e.g. "10:00" or "11:00", etc.
  # We'll do a simplified guess for demonstration:
  hex_msg="1F:82:10:00"
  switch_source_cmd="tx $hex_msg"

  echo "Attempting: $switch_source_cmd"
  run_cec_command "$switch_source_cmd"

  if prompt_yes_no "Did the TV switch input now"; then
    echo "Great, storing '$switch_source_cmd' as the working switch-source command."
  else
    echo "No success. We'll store no command for switching source."
    switch_source_cmd=""
  fi
fi

echo ""
echo "Done with Switch Source test."
echo ""

###############################################################################
# Summary & Save
###############################################################################
echo "========================================"
echo "Summary of your tested commands:"
echo "----------------------------------------"
echo "Power Off:    $power_off_cmd"
echo "Power On:     $power_on_cmd"
echo "Switch Input: $switch_source_cmd"
echo "========================================"
echo ""

save_config "$device_addr" "$power_off_cmd" "$power_on_cmd" "$switch_source_cmd"

echo ""
echo "Wizard complete! Next time, you can run these stored commands directly:"
echo "----------------------------------------"
echo "  Power Off:    echo \"$power_off_cmd\" | cec-client -s -d 8 $CEC_ADAPTER"
echo "  Power On:     echo \"$power_on_cmd\"  | cec-client -s -d 8 $CEC_ADAPTER"
echo "  Switch Input: echo \"$switch_source_cmd\" | cec-client -s -d 8 $CEC_ADAPTER"
echo "----------------------------------------"
echo "Have a nice day!"
