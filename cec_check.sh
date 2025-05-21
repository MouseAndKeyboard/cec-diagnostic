#!/usr/bin/env bash
#
# cec_wizard_manual_partial.sh — HDMI-CEC diagnostic with partial manual input
#
# 1. Enter adapter and addresses manually
# 2. Determine power-off, power-on, switch-to-Pi, switch-away commands
# 3. Write ./cec_config.json
#
# Make executable: chmod +x cec_wizard_manual_partial.sh
#

set -e

CONFIG=cec_config.json

###############################################################################
# Helper: require cec-client
###############################################################################
command -v cec-client >/dev/null 2>&1 || {
  echo >&2 "cec-client not found.  sudo apt-get install cec-utils"; exit 1; }

###############################################################################
# 1. Enter adapter and addresses manually                                    ###
###############################################################################
read -rp "Enter CEC adapter path (/dev/cecN): " CEC_ADAPTER
read -rp "Enter Pi's logical address (hex): " PI_ADDR
read -rp "Enter TV's logical address (hex): " TV_ADDR

###############################################################################
# 2. Determine power-off, power-on, switch-to-Pi, switch-away commands        ###
###############################################################################
echo
echo "Testing power-off command..."
POFF="tx ${PI_ADDR}${TV_ADDR}:36"
echo "$POFF" | cec-client -s -d 8 "$CEC_ADAPTER"
echo "Did the TV power off? (y/n)"
read -r ans
[[ "$ans" == "n" ]] && POFF=""

echo
echo "Testing power-on command..."
PON="tx ${PI_ADDR}${TV_ADDR}:04"
echo "$PON" | cec-client -s -d 8 "$CEC_ADAPTER"
echo "Did the TV power on? (y/n)"
read -r ans
[[ "$ans" == "n" ]] && PON=""

echo
echo "Testing switch-to-Pi command..."
SW_TO_PI="as"
echo "$SW_TO_PI" | cec-client -s -d 8 "$CEC_ADAPTER"
echo "Did the TV switch to Pi's HDMI input? (y/n)"
read -r ans
[[ "$ans" == "n" ]] && SW_TO_PI=""

echo
echo "Testing switch-away command (try any external source)..."
SW_AWAY=""
# Iterate over all logical addresses except Pi and TV
for L in $(seq 0 15); do
  [[ "$L" == "$PI_ADDR" || "$L" == "$TV_ADDR" ]] && continue
  SW_AWAY="tx ${PI_ADDR}F:82:0${L}:00"
  echo "$SW_AWAY" | cec-client -s -d 8 "$CEC_ADAPTER"
  echo "Did the TV switch away to logical $L? (y/n)"
  read -r ans
  [[ "$ans" == "y" ]] && break
  SW_AWAY=""
done

###############################################################################
# 3. Write configuration                                                      ###
###############################################################################
cat > "$CONFIG" <<EOF
{
  "adapter":      "$CEC_ADAPTER",
  "pi_addr":      "$PI_ADDR",
  "tv_addr":      "$TV_ADDR",
  "power_off":    "$POFF",
  "power_on":     "$PON",
  "switch_to_pi": "$SW_TO_PI",
  "switch_away":  "$SW_AWAY"
}
EOF

echo
echo "Configuration saved to $CONFIG"
echo "Wizard complete."
