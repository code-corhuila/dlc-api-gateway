#!/usr/bin/env bash
# Annex F checks run against a running gateway.
# Usage: GATEWAY_URL=http://localhost:8080 SMOKE_ORIGIN=http://localhost:8080 [GATEWAY_CONTAINER=name] tests/smoke.sh
# SMOKE_ORIGIN must equal GATEWAY_ALLOWED_ORIGIN of the gateway. GATEWAY_CONTAINER enables the log check.
set -u

GATEWAY_URL="${GATEWAY_URL:-http://localhost:8080}"
SMOKE_ORIGIN="${SMOKE_ORIGIN:-http://localhost:8080}"
GATEWAY_CONTAINER="${GATEWAY_CONTAINER:-}"
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
header_value() { grep -i "^$1:" "$headers_file" | head -1 | cut -d: -f2- | tr -d " "; }

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

# Correlation: generated when absent, kept when valid, replaced when malformed
request GET /api/v1/does-not-exist
generated="$(header_value X-Correlation-Id)"
check "correlation id is generated when absent" '[ -n "$generated" ]'
check "generated correlation id is the envelope traceId" '[ -n "$generated" ] && body_has "\"traceId\":\"$generated\""'

sent="smoke-$(date +%s)-$RANDOM"
request GET /api/v1/does-not-exist -H "X-Correlation-Id: $sent"
check "valid correlation id is kept" '[ "$(header_value X-Correlation-Id)" = "$sent" ]'
check "kept correlation id is the envelope traceId" 'body_has "\"traceId\":\"$sent\""'

request GET /health -H "X-Correlation-Id: bad id with spaces"
check "malformed correlation id is replaced" 'v="$(header_value X-Correlation-Id)"; [ -n "$v" ] && [ "$v" != "badidwithspaces" ]'

if [ -n "$GATEWAY_CONTAINER" ]; then
  sleep 1
  check "gateway log records the correlation id" 'docker logs "$GATEWAY_CONTAINER" 2>/dev/null | grep -q "\"correlationId\":\"$sent\""'
fi

# CORS: only the container origin, the four Norma 5.6.4 headers, exposed X-Correlation-Id and Location
request OPTIONS /api/v1/patients -H "Origin: $SMOKE_ORIGIN" -H "Access-Control-Request-Method: POST" -H "Access-Control-Request-Headers: authorization, content-type, idempotency-key, x-correlation-id"
check "preflight from container origin responds 204" '[ "$status" = 204 ]'
check "preflight allows the container origin" '[ "$(header_value Access-Control-Allow-Origin)" = "$SMOKE_ORIGIN" ]'
check "preflight allows Idempotency-Key and the other norm headers" '( h="$(header_value Access-Control-Allow-Headers | tr A-Z a-z)"; for x in authorization content-type idempotency-key x-correlation-id; do case ",$h," in *",$x,"*) ;; *) exit 1;; esac; done )'
check "preflight never answers a wildcard origin" '[ "$(header_value Access-Control-Allow-Origin)" != "*" ] && ! header_has "^Access-Control-Allow-Credentials: true"'

request GET /health -H "Origin: $SMOKE_ORIGIN"
check "response exposes X-Correlation-Id and Location" '( h="$(header_value Access-Control-Expose-Headers | tr A-Z a-z)"; case ",$h," in *",x-correlation-id,"*) ;; *) exit 1;; esac; case ",$h," in *",location,"*) ;; *) exit 1;; esac )'

request GET /health -H "Origin: https://unknown.example"
check "unknown origin gets no Access-Control-Allow-Origin" '! header_has "^Access-Control-Allow-Origin:"'

request OPTIONS /api/v1/patients -H "Origin: https://unknown.example" -H "Access-Control-Request-Method: POST"
check "preflight from unknown origin gets no Access-Control-Allow-Origin" '! header_has "^Access-Control-Allow-Origin:"'

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "All checks passed"
