#!/usr/bin/env bash
# Annex F checks run against a running gateway. Usage: GATEWAY_URL=http://localhost:8080 tests/smoke.sh
set -u

GATEWAY_URL="${GATEWAY_URL:-http://localhost:8080}"
failures=0
body_file="$(mktemp)"
headers_file="$(mktemp)"
trap 'rm -f "$body_file" "$headers_file"' EXIT

# request METHOD PATH [curl args...] -> sets $status; body in $body_file, headers in $headers_file
request() {
  local method="$1" path="$2"
  shift 2
  status="$(curl -s -o "$body_file" -D "$headers_file" -w '%{http_code}' -X "$method" "$@" "${GATEWAY_URL}${path}" || true)"
}

check() {
  local name="$1" condition="$2"
  if eval "$condition"; then
    echo "PASS  $name"
  else
    echo "FAIL  $name (status=$status body=$(head -c 300 "$body_file"))"
    failures=$((failures + 1))
  fi
}

body_has() { grep -q -- "$1" "$body_file"; }
header_has() { grep -qi -- "$1" "$headers_file"; }

# /health of the gateway itself
request GET /health
check "health responds 200" '[ "$status" = 200 ]'
check "health reports UP" 'body_has "\"status\":\"UP\""'

# Unknown route under /api/v1 uses the common envelope
request GET /api/v1/does-not-exist
check "unknown api route responds 404" '[ "$status" = 404 ]'
check "unknown api route uses NOT_FOUND envelope" 'body_has "\"error\":\"NOT_FOUND\"" && body_has "\"message\":" && body_has "\"traceId\":"'
check "unknown api route is JSON" 'header_has "^Content-Type: application/json"'

# Any other path also answers with the envelope
request GET /not-a-route
check "unknown root path responds 404 with envelope" '[ "$status" = 404 ] && body_has "\"error\":\"NOT_FOUND\""'

# Private coordination routes are never exposed
request GET /internal/v1/sessions/validations
check "internal routes are not exposed" '[ "$status" = 404 ] && body_has "\"error\":\"NOT_FOUND\""'

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "All checks passed"
