#!/usr/bin/env bash
# Keeps a DuckDNS hostname pointed at this network's current public IP.
#
# minecraft.sonic-art.co.uk is a CNAME to that DuckDNS hostname, so players
# keep resolving to the right address when the ISP hands us a new IP.
# Without this, an IP change silently breaks external play - which is what
# happened in January 2026 and went unnoticed for nine months.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$DIR/ddns.conf"
LOG="$DIR/ddns.log"
STATE="$DIR/last-ip"

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG"; }

if [[ ! -r "$CONF" ]]; then
    log "ERROR: $CONF is missing or unreadable"
    exit 1
fi
# shellcheck source=/dev/null
source "$CONF"

if [[ -z "${DUCKDNS_DOMAIN:-}" || -z "${DUCKDNS_TOKEN:-}" ]]; then
    log "ERROR: set DUCKDNS_DOMAIN and DUCKDNS_TOKEN in $CONF"
    exit 1
fi
if [[ "$DUCKDNS_TOKEN" == PASTE-* || "$DUCKDNS_DOMAIN" == PASTE-* ]]; then
    log "NOT CONFIGURED: $CONF still holds the placeholder values"
    exit 1
fi

# An empty ip= tells DuckDNS to use the source address of this request, which
# is exactly the public address we want players to reach us on. Only IPv4 is
# published on purpose: an AAAA record would have clients prefer IPv6, which
# fails if inbound v6 is blocked upstream or the player has no v6 at all.
if ! resp="$(curl -fsS --max-time 20 \
    "https://www.duckdns.org/update?domains=${DUCKDNS_DOMAIN}&token=${DUCKDNS_TOKEN}&ip=")"; then
    log "ERROR: could not reach DuckDNS"
    exit 1
fi
if [[ "$resp" != OK* ]]; then
    log "ERROR: DuckDNS replied '${resp}' - check the domain and token"
    exit 1
fi

# Log only when the address actually moves, so the log stays worth reading.
new="$(getent hosts "${DUCKDNS_DOMAIN}.duckdns.org" | awk '{print $1; exit}')"
prev="$(cat "$STATE" 2>/dev/null || echo none)"
if [[ -n "$new" && "$new" != "$prev" ]]; then
    log "public IP now ${new} (was ${prev})"
    printf '%s\n' "$new" >"$STATE"
fi

# Keep the log from growing without bound.
if [[ -f "$LOG" ]] && (( $(wc -l <"$LOG") > 500 )); then
    tail -n 200 "$LOG" >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi
