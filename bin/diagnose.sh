#!/usr/bin/env bash
# diagnose.sh — one-shot printer identification + test print
#
# Usage:
#   ./bin/diagnose.sh <printer-ip>                       # safe probe + Big5 test print
#   ./bin/diagnose.sh <printer-ip> --encoding gbk        # use Simplified Chinese
#   ./bin/diagnose.sh <printer-ip> --no-print            # info-only, do not print
#   ./bin/diagnose.sh <printer-ip> --deep                # enable invasive probes
#
# What it does:
#   1. Checks route to printer; if VPN is in the way, offers to add a host route
#      bypass via the local LAN gateway (needs sudo once).
#   2. Pings to confirm L3 reachability.
#   3. Runs the full 7-channel safe probe; prints a receipt (Big5 by default,
#      matching the HK market) if protocol == ESC/POS.
#
# Output stays in your terminal — paste it into the PR / Slack as the demo
# evidence.

set -euo pipefail

if [[ $# -lt 1 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
  sed -nE 's/^# ?(.*)/\1/p' "$0" | head -25
  exit 64
fi

IP="$1"; shift

DO_PRINT=true
ENCODING="big5"
EXTRA=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-print)    DO_PRINT=false; shift ;;
    --encoding)    ENCODING="$2"; shift 2 ;;
    *)             EXTRA+=("$1"); shift ;;
  esac
done

# Use fvm if present, otherwise fall back to plain dart.
DART=(fvm dart)
command -v fvm >/dev/null 2>&1 || DART=(dart)

# ---- Step 1: route check ----
echo "== Pre-flight: route to $IP =="
RAW=$(route -n get "$IP" 2>&1 || true)
IFACE=$(awk '/interface:/ {print $2}' <<<"$RAW")
GW=$(awk '/gateway:/ {print $2}' <<<"$RAW")

if [[ "$IFACE" =~ ^utun ]]; then
  # Derive LAN gateway from en0 (Wi-Fi or wired). Heuristic: x.y.z.1 of en0's IP.
  EN0_IP=$(ifconfig en0 inet 2>/dev/null | awk '/inet / {print $2; exit}')
  if [[ -z "${EN0_IP:-}" ]]; then
    echo "✗ $IP routes via VPN ($IFACE) and en0 has no IPv4. Aborting."
    exit 1
  fi
  LAN_GW="${EN0_IP%.*}.1"
  echo "⚠  $IP currently routes through VPN ($IFACE → $GW)."
  echo "   Adding host route via LAN gateway $LAN_GW (sudo required)."
  sudo route -n add -host "$IP" "$LAN_GW" 2>&1 || {
    echo "✗ Failed to add bypass route. Disconnect VPN and retry."
    exit 1
  }
  echo "✓ Bypass route installed."
else
  echo "✓ routes via $IFACE (gateway $GW)"
fi

# ---- Step 2: ping ----
echo
echo "== Reachability =="
if ping -c 2 -W 1500 "$IP" >/dev/null 2>&1; then
  echo "✓ ping OK"
else
  echo "✗ $IP unreachable. Check power / cable / network."
  exit 1
fi

# ---- Step 3: probe (+ print) ----
echo
echo "== Probe + ${DO_PRINT:+Print + }Report =="
ARGS=("$IP" --encoding "$ENCODING")
$DO_PRINT && ARGS+=(--print)
if [[ ${#EXTRA[@]} -gt 0 ]]; then
  ARGS+=("${EXTRA[@]}")
fi

"${DART[@]}" run bin/printer_probe.dart "${ARGS[@]}"
