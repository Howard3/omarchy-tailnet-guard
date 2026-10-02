#!/usr/bin/env bash
# The daemon must keep refreshing status after it forks its watchers.
# A lock fd inherited by those watchers pins flock for the whole session
# and freezes status on the boot-time sample.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$ROOT/bin/tailnet-guard"

tmp="$(mktemp -d)"
cleanup() {
  if [[ -n ${pid:-} ]]; then
    # setsid puts the daemon in its own process group, so this also reaps
    # the watcher pipeline if a trapped signal does not take them down.
    kill -- -"$pid" 2>/dev/null || true
    sleep 0.3
    kill -KILL -- -"$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

mkdir -p "$tmp/state"
export TAILNET_GUARD_STATE="$tmp/state"
export TAILNET_GUARD_CONFIG="$tmp/tailnet-guard.json"
export TAILNET_GUARD_CONFIG_JSON='{"version":1,"defaultPolicy":"deny","safe":["Home"],"unsafe":[],"notify":false}'
export TAILNET_GUARD_IDENTITY_JSON='{"phase":"connected","kind":"wifi","ssid":"Home","connection":"Home","device":"wlan0"}'
export TAILNET_GUARD_DRY_RUN=1

setsid "$GUARD" run >/dev/null 2>&1 &
pid=$!

for _ in $(seq 1 50); do
  [[ -f $tmp/state/status.json ]] && break
  sleep 0.1
done
[[ -f $tmp/state/status.json ]] || { echo "FAIL status never written" >&2; exit 1; }

# Let startup finish and the watchers fork, which is where the lock used to leak.
sleep 1

if ! flock -w 2 "$tmp/state/daemon.lock" -c true; then
  echo "FAIL daemon.lock still held after startup" >&2
  exit 1
fi

before="$(jq -r '.updatedAt' "$tmp/state/status.json")"
sleep 7
after="$(jq -r '.updatedAt' "$tmp/state/status.json")"
reason="$(jq -r '.reason' "$tmp/state/status.json")"
phase="$(jq -r '.phase' "$tmp/state/status.json")"

if [[ $before == "$after" ]]; then
  echo "FAIL status frozen at $before ($phase/$reason)" >&2
  exit 1
fi
if [[ $phase != connected || $reason != safe-network ]]; then
  echo "FAIL status $phase/$reason" >&2
  exit 1
fi

echo "ok daemon refreshes status and releases its lock"
