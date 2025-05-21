#!/usr/bin/env bash
#
# cec_wizard.sh — Plug-and-play HDMI-CEC diagnostic for Raspberry Pi
#
# 1. Detect adapter(s)     4. Test power-on
# 2. Scan devices          5. Test switch-to-Pi
# 3. Test power-off        6. Test switch-away
#               7. Write ./cec_config.json
#
# Make executable: chmod +x cec_wizard.sh
#

set -e

CONFIG=cec_config.json
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

###############################################################################
# Helper: require cec-client
###############################################################################
command -v cec-client >/dev/null 2>&1 || {
  echo >&2 "cec-client not found.  sudo apt-get install cec-utils"; exit 1; }

###############################################################################
# Helper: choose adapter (/dev/cecN)                                        ###
###############################################################################
choose_adapter() {
  local devs=( /dev/cec* )
  if (( ${#devs[@]} == 0 )); then
      echo "No /dev/cec* devices found — check cabling!" ; exit 1
  elif (( ${#devs[@]} == 1 )); then
      CEC_ADAPTER=${devs[0]}
      echo "Using adapter: $CEC_ADAPTER"
  else
      echo "Multiple CEC adapters detected:"
      local i=0
      for d in "${devs[@]}"; do echo "  [$i] $d"; ((i++)); done
      while true; do
          read -rp "Pick adapter number [0-${#devs[@]}-1, Enter=0]: " idx
          idx=${idx:-0}
          if [[ $idx =~ ^[0-9]+$ ]] && (( idx>=0 && idx<${#devs[@]} )); then
              CEC_ADAPTER=${devs[$idx]}
              echo "Using adapter: $CEC_ADAPTER"
              break
          else
              echo "  ⇢ Invalid choice '$idx'. Try again."
          fi
      done
  fi
}


###############################################################################
# Helper: run a silent cec-client one-shot command                           ###
###############################################################################
cec_cmd() { echo "$1" | cec-client -s -d 8 "$CEC_ADAPTER" 2>/dev/null; }

###############################################################################
# Helper: yes/no prompt                                                      ###
###############################################################################
confirm() { while true; do read -rp "$1 (y/n) " r; case $r in [Yy]*) return 0;; [Nn]*) return 1;; esac; done; }

###############################################################################
# 1. Pick adapter                                                             #
###############################################################################
choose_adapter
echo

###############################################################################
# 2. Scan devices and pretty-print table                                      #
###############################################################################
echo "Scanning HDMI-CEC bus ..."
cec_cmd "scan" > "$TMP"
echo
echo "Found devices:"
awk '/device #/{printf "\n%-8s %-12s %-10s %-s", $2, $3, $4, $0}
     /logical address/{printf "  (logical=%s)", $3}
     /physical address/{printf "  (phys=%s)", $3}' "$TMP" | column -t
echo

# Collect arrays of logical & physical addresses (hex without dots)
mapfile -t LOG_ADDRS < <(awk '/logical address/ {print $3}' "$TMP")
mapfile -t PHYS_ADDRS < <(awk '/physical address/ {gsub(/\./,"",$3); print $3}' "$TMP")
DEVCOUNT=${#LOG_ADDRS[@]}

read -rp "Which logical address is the TV? [default 0] " TV_ADDR
TV_ADDR=${TV_ADDR:-0}

###############################################################################
# 3. Determine Pi logical-address                                             #
###############################################################################
echo
echo "Detecting Pi's logical address ..."
# Start cec-client for one second just to watch assignment line
CEC_LINE=$(timeout 1s cec-client -o Wizard -d 8 "$CEC_ADAPTER" 2>&1 | \
           grep -m1 -Eo 'logical address set to (.+)$' || true)

if [[ $CEC_LINE =~ ([0-9])$ ]]; then
  PI_ADDR=${BASH_REMATCH[1]}
  echo "  libCEC assigned address $PI_ADDR"
else
  echo "libCEC didn’t report its address; will probe common ones (1,4)."
  for cand in 1 4; do
      echo -n "  Trying standby from $cand->$TV_ADDR ... "
      cec_cmd "tx $(printf '%X%X' $cand $TV_ADDR):36"
      if confirm "Did the TV turn off?"; then
          PI_ADDR=$cand; echo "Selected $PI_ADDR"; break
      else echo "no"; fi
  done
  [[ -z $PI_ADDR ]] && { echo "Cannot determine Pi address."; exit 1; }
  # Turn TV back on for remaining tests
  cec_cmd "tx $(printf '%X%X' $PI_ADDR $TV_ADDR):04"
fi

###############################################################################
# 4. Test power-off / power-on                                               #
###############################################################################
echo
echo "============== POWER TESTS =============="

POFF="standby $TV_ADDR"
cec_cmd "$POFF"
if ! confirm "Did the TV power off"; then
  POFF="tx $(printf '%X%X' $PI_ADDR $TV_ADDR):36"
  cec_cmd "$POFF"
  confirm "TV off now?" || POFF=""
fi

# Power back on
PON="on $TV_ADDR"
cec_cmd "$PON"
if ! confirm "Did the TV power on"; then
  PON="tx $(printf '%X%X' $PI_ADDR $TV_ADDR):04"
  cec_cmd "$PON"
  confirm "TV on now?" || PON=""
fi

###############################################################################
# 5. Test switch-to-Pi (Active Source)                                       #
###############################################################################
echo
echo "=========== INPUT-SWITCH TESTS =========="

SW_TO_PI="as"
cec_cmd "$SW_TO_PI"
confirm "Did the TV switch to the Pi's HDMI input?" || SW_TO_PI=""

###############################################################################
# 6. Test switch-away (choose first other device that works)                 #
###############################################################################
SW_AWAY=""
for i in $(seq 0 $((DEVCOUNT-1))); do
  L=${LOG_ADDRS[$i]}
  P=${PHYS_ADDRS[$i]}
  [[ $L == "$TV_ADDR" || $L == "$PI_ADDR" ]] && continue
  MSG="tx $(printf '%X%X' $PI_ADDR 0xF):82:${P:0:2}:${P:2:2}"
  cec_cmd "$MSG"
  if confirm "Did the TV switch away to logical $L (phys ${P:0:1}.${P:1:1}.0.0)"; then
     SW_AWAY=$MSG; break
  fi
done
[[ -z $SW_AWAY ]] && echo "No external source change succeeded."

###############################################################################
# 7. Write configuration                                                     #
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
echo "========================================"
echo "Saved working configuration to $CONFIG:"
jq . "$CONFIG" 2>/dev/null || cat "$CONFIG"
echo "========================================"
echo "Wizard complete."
