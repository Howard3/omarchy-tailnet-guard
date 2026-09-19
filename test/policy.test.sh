#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$ROOT/bin/tailnet-guard"

decide() {
  local identity=$1 config=$2
  TAILNET_GUARD_IDENTITY_JSON="$identity" \
    TAILNET_GUARD_CONFIG_JSON="$config" \
    TAILNET_GUARD_DRY_RUN=1 \
    "$GUARD" decide
}

expect() {
  local name=$1 identity=$2 config=$3 want_decision=$4 want_reason=$5
  local got
  got="$(decide "$identity" "$config")"
  local decision reason
  decision="$(jq -r '.decision' <<<"$got")"
  reason="$(jq -r '.reason' <<<"$got")"
  if [[ $decision != "$want_decision" || $reason != "$want_reason" ]]; then
    echo "FAIL $name" >&2
    echo "  wanted $want_decision/$want_reason" >&2
    echo "  got    $decision/$reason" >&2
    echo "  $got" >&2
    exit 1
  fi
  echo "ok $name"
}

DENY='{"defaultPolicy":"deny","safe":["Home"],"unsafe":["Hotel"],"notify":false}'
ALLOW='{"defaultPolicy":"allow","safe":["Home"],"unsafe":["Hotel"],"notify":false}'

expect disconnected \
  '{"phase":"disconnected","kind":"none","ssid":"","connection":""}' \
  "$DENY" down between-networks

expect connecting \
  '{"phase":"connecting","kind":"wifi","ssid":"","connection":"Home"}' \
  "$DENY" down between-networks

expect sleeping \
  '{"phase":"sleeping","kind":"none","ssid":"","connection":""}' \
  "$ALLOW" down sleeping

expect unknown-deny \
  '{"phase":"connected","kind":"wifi","ssid":"Cafe","connection":"Cafe"}' \
  "$DENY" down unknown-deny

expect safe-ssid \
  '{"phase":"connected","kind":"wifi","ssid":"Home","connection":"Home"}' \
  "$DENY" up safe-network

expect match-connection-name \
  '{"phase":"connected","kind":"wifi","ssid":"","connection":"Home"}' \
  "$DENY" up safe-network

expect unsafe-wins \
  '{"phase":"connected","kind":"wifi","ssid":"Hotel","connection":"Home"}' \
  "$DENY" down unsafe-network

expect default-allow \
  '{"phase":"connected","kind":"wifi","ssid":"Cafe","connection":"Cafe"}' \
  "$ALLOW" up default-allow

expect default-allow-still-blocks-listed \
  '{"phase":"connected","kind":"wifi","ssid":"Hotel","connection":"Hotel"}' \
  "$ALLOW" down unsafe-network

expect default-allow-still-down-between \
  '{"phase":"connecting","kind":"wifi","ssid":"Home","connection":"Home"}' \
  "$ALLOW" down between-networks

expect ethernet-safe \
  '{"phase":"connected","kind":"ethernet","ssid":"","connection":"Wired connection 1"}' \
  '{"defaultPolicy":"deny","safe":["Wired connection 1"],"unsafe":[]}' \
  up safe-network

echo "all tests passed"
