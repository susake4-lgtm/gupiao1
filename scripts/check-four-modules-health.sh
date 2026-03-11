#!/usr/bin/env bash
set -euo pipefail

DSA_URL="${DSA_HEALTH_URL:-http://127.0.0.1:8000/api/health}"
FUTURES_URL="${FUTURES_HEALTH_URL:-http://127.0.0.1:8010/api/futures/health}"
OPENCLAW_URL="${OPENCLAW_URL:-http://127.0.0.1:18789}"
TRENDRADAR_URL="${TRENDRADAR_URL:-http://127.0.0.1:3334}"

status_ok=true

check_http() {
  local name="$1"
  local url="$2"

  if curl -sS --max-time 3 "$url" >/dev/null 2>&1; then
    echo "[health] $name ok: $url"
  else
    echo "[health] $name fail: $url" >&2
    status_ok=false
  fi
}

check_http "dsa(8000)" "$DSA_URL"
check_http "futures(8010)" "$FUTURES_URL"
check_http "openclaw(18789)" "$OPENCLAW_URL"
check_http "trendradar(3334)" "$TRENDRADAR_URL"

if [[ "$status_ok" != true ]]; then
  exit 1
fi
