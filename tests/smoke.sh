#!/usr/bin/env bash
# Annex F checks run against a running gateway.
# Runs against tests/compose.smoke.yml (gateway plus stand-in owner services):
#   docker compose -f tests/compose.smoke.yml up -d --build
#   GATEWAY_URL=http://localhost:18080 GATEWAY_CONTAINER=dlc-smoke-gateway \
#   SMOKE_STUB_CONTAINER=dlc-smoke-patients-api SMOKE_STOP_CONTAINER=dlc-smoke-auth-service SMOKE_PROXY_URL=http://localhost:18081 bash tests/smoke.sh
# SMOKE_ORIGIN must equal GATEWAY_ALLOWED_ORIGIN. The *_CONTAINER variables enable the log and
# stopped-service checks; SMOKE_STOP_CONTAINER is stopped by the script.
set -u

GATEWAY_URL="${GATEWAY_URL:-http://localhost:8080}"
SMOKE_ORIGIN="${SMOKE_ORIGIN:-http://localhost:8080}"
GATEWAY_CONTAINER="${GATEWAY_CONTAINER:-}"
SMOKE_STUB_CONTAINER="${SMOKE_STUB_CONTAINER:-}"
SMOKE_STOP_CONTAINER="${SMOKE_STOP_CONTAINER:-}"
SMOKE_PROXY_URL="${SMOKE_PROXY_URL:-}"
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
check "generated correlation id is a version 4 UUID (owners put it in event metadata)" 'echo "$generated" | grep -Eq "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"'

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

# Domain routes (smoke environment): each owner route reaches its service with /api/v1 preserved
TOKEN="Bearer smoke-token"
for pair in "patients:/api/v1/patients" "patients:/api/v1/patients/0b1c" \
            "appointments:/api/v1/appointments" "appointments:/api/v1/dentists/0b1c/availability" "appointments:/api/v1/clinical-assignments" \
            "clinical:/api/v1/clinical-records/0b1c/entries" "clinical:/api/v1/treatments" "clinical:/api/v1/procedures/0b1c/completions" \
            "clinical:/api/v1/care-closures/0b1c" "clinical:/api/v1/clinical-entries/0b1c/amendments" "clinical:/api/v1/clinical-analytics/dashboard" \
            "billing:/api/v1/invoices" "billing:/api/v1/procedure-prices" "billing:/api/v1/additional-price-rules" "billing:/api/v1/billable-items" "billing:/api/v1/manual-charges" \
            "iam:/api/v1/auth/staff"; do
  service="${pair%%:*}"; path="${pair#*:}"
  request GET "$path" -H "Authorization: $TOKEN"
  check "$path routes to $service" '[ "$status" = 200 ] && body_has "\"service\":\"$service\"" && body_has "\"path\":\"$path\""'
done

request GET /api/v1/patientsx -H "Authorization: $TOKEN"
check "a lookalike prefix is not routed" '[ "$status" = 404 ] && body_has "\"message\":\"The requested route does not exist.\""'

# Credential presence filter (Norma 5.6.2): protected route without Authorization
request GET /api/v1/patients
check "protected route without Authorization responds 401" '[ "$status" = 401 ]'
check "401 uses the UNAUTHORIZED envelope with traceId" 'body_has "\"error\":\"UNAUTHORIZED\"" && body_has "\"traceId\":"'
check "401 carries a Bearer challenge and the correlation id" 'header_has "^WWW-Authenticate: Bearer" && [ -n "$(header_value X-Correlation-Id)" ]'
request GET /api/v1/auth/staff
check "protected Auth route without Authorization responds 401" '[ "$status" = 401 ] && body_has "\"error\":\"UNAUTHORIZED\""'

# Public Auth entry points reach IAM without Authorization (security: [] in the contract)
for path in /api/v1/auth/email-verifications /api/v1/auth/password-recovery-requests /api/v1/auth/password-resets \
            /api/v1/auth/jwks /api/v1/auth/refresh /api/v1/auth/logout /api/v1/auth/csrf; do
  request GET "$path"
  check "public $path reaches IAM without Authorization" '[ "$status" = 200 ] && body_has "\"service\":\"iam\""'
done

# dlc-docs#127 criterion 3: routed login keeps body, refresh cookie and no-store unchanged
request POST /api/v1/auth/login -H "Content-Type: application/json" --data '{"email":"a@b.c","password":"x"}'
check "routed login keeps the IAM body" '[ "$status" = 200 ] && body_has "\"accessToken\":\"stub-access\""'
check "routed login keeps the HttpOnly Secure SameSite refresh cookie" 'header_has "^Set-Cookie: dlc_refresh=stub-refresh; Path=/api/v1/auth; HttpOnly; Secure; SameSite=Strict"'
check "routed login keeps Cache-Control no-store" 'header_has "^Cache-Control: no-store"'

# dlc-docs#126 criterion 4: caller-supplied identity headers never reach the owner
request GET /api/v1/auth/staff -H "Authorization: $TOKEN" -H "X-User-Id: forged-admin" -H "X-User-Role: ADMINISTRATOR"
check "caller-supplied X-User-Id and X-User-Role are stripped" 'body_has "\"xUserId\":\"\"" && body_has "\"xUserRole\":\"\""'
check "Authorization is forwarded for owner-side validation" 'body_has "\"authorization\":\"$TOKEN\""'

# Owner errors pass through untouched
request GET /api/v1/invoices/missing -H "Authorization: $TOKEN"
check "owner error passes through untouched" '[ "$status" = 404 ] && body_has "\"message\":\"Reported by billing\""'

# Correlation reaches the service, comes back and is logged by both
routed="smoke-routed-$(date +%s)-$RANDOM"
request GET /api/v1/patients -H "Authorization: $TOKEN" -H "X-Correlation-Id: $routed"
check "correlation id is forwarded to the service" 'body_has "\"correlationId\":\"$routed\""'
check "correlation id is returned once" '[ "$(grep -ci "^X-Correlation-Id:" "$headers_file")" = 1 ] && [ "$(header_value X-Correlation-Id)" = "$routed" ]'
if [ -n "$SMOKE_STUB_CONTAINER" ]; then
  sleep 1
  check "service log records the correlation id" 'docker logs "$SMOKE_STUB_CONTAINER" 2>/dev/null | grep -q "\"correlationId\":\"$routed\""'
fi

# A stopped domain answers 503 on its route only (Norma 5.6.3). Runs last: it stops a container.
if [ -n "$SMOKE_STOP_CONTAINER" ]; then
  docker stop "$SMOKE_STOP_CONTAINER" >/dev/null
  sleep 1
  request GET /api/v1/auth/jwks
  check "stopped service route responds 503 SERVICE_UNAVAILABLE" '[ "$status" = 503 ] && body_has "\"error\":\"SERVICE_UNAVAILABLE\"" && body_has "\"traceId\":"'
  request GET /api/v1/patients -H "Authorization: $TOKEN"
  check "other routes keep working" '[ "$status" = 200 ] && body_has "\"service\":\"patients\""'
  request GET /health
  check "gateway stays healthy" '[ "$status" = 200 ]'
fi


# Rate limits (Norma 5.6, explicit): run last because they exhaust the per-IP budgets.
# Login: 10 attempts per IP in five minutes. The routed login check above already spent one.
login_status=""
for i in $(seq 1 12); do
  request POST /api/v1/auth/login -H "Content-Type: application/json" --data '{}'
  if [ "$status" = 429 ]; then login_status=429; break; fi
done
check "login is limited to 10 attempts per IP (429 within 12)" '[ "$login_status" = 429 ] && [ "$i" -le 11 ]'
check "429 uses the TOO_MANY_REQUESTS envelope with traceId" 'body_has "\"error\":\"TOO_MANY_REQUESTS\"" && body_has "\"traceId\":"'
check "429 carries Retry-After" '[ -n "$(header_value Retry-After)" ]'
check "429 carries the correlation id" '[ -n "$(header_value X-Correlation-Id)" ]'

# General API: 100 requests per minute per IP with a burst of 50
general_status=""
for i in $(seq 1 250); do
  request GET /api/v1/patients -H "Authorization: $TOKEN"
  if [ "$status" = 429 ]; then general_status=429; break; fi
done
check "general API limit answers 429 once the burst is spent" '[ "$general_status" = 429 ] && body_has "\"error\":\"TOO_MANY_REQUESTS\"" && [ -n "$(header_value Retry-After)" ]'
request GET /health
check "health is not rate limited" '[ "$status" = 200 ]'


# Client address behind the trusted proxy (dlc-front): budgets are per browser, not per proxy.
# Runs after the rate limits above, so this host's own budgets are already spent.
if [ -n "$SMOKE_PROXY_URL" ]; then
  direct_url="$GATEWAY_URL"
  # A client outside the trusted proxy cannot mint fresh budgets by sending a different address each time.
  spoof_status=""
  for n in 1 2 3 4 5; do
    request POST /api/v1/auth/login -H "Content-Type: application/json" -H "X-Forwarded-For: 198.51.100.$n" --data '{}'
    if [ "$status" = 429 ]; then spoof_status=429; break; fi
  done
  check "X-Forwarded-For from an untrusted client is ignored (one budget, 429 within 5)" '[ "$spoof_status" = 429 ]'

  GATEWAY_URL="$SMOKE_PROXY_URL"
  request POST /api/v1/auth/login -H "Content-Type: application/json" -H "X-Test-Client-Ip: 203.0.113.10" --data '{}'
  check "a browser behind the trusted proxy has its own login budget" '[ "$status" != 429 ]'
  proxied_status=""
  for i in $(seq 1 12); do
    request POST /api/v1/auth/login -H "Content-Type: application/json" -H "X-Test-Client-Ip: 203.0.113.10" --data '{}'
    if [ "$status" = 429 ]; then proxied_status=429; break; fi
  done
  check "that browser is limited once its own 10 attempts are spent" '[ "$proxied_status" = 429 ]'
  request POST /api/v1/auth/login -H "Content-Type: application/json" -H "X-Test-Client-Ip: 203.0.113.11" --data '{}'
  check "another browser behind the same proxy is not limited by the first one" '[ "$status" != 429 ]'
  request GET /api/v1/patients -H "Authorization: $TOKEN" -H "X-Test-Client-Ip: 203.0.113.12"
  check "general API budget is also per browser behind the proxy" '[ "$status" = 200 ]'
  GATEWAY_URL="$direct_url"
fi


if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "All checks passed"
