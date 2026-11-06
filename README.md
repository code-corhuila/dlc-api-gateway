# dlc-api-gateway

> Single public HTTP entry point — routing, edge credential checks and rate limiting.

Part of the **Di Lucca Dental Care & Technology** distributed system. The Gateway routes staff web requests on `/api/v1` to the owner APIs (Auth/IAM, Patients, Appointments, Clinical and Billing). It is a supporting component, not a business service: it owns no patient, appointment, clinical or financial data and has no business datastore. Each owner service rechecks resource authorization; the Gateway never exposes private `/internal/v1` routes.

Governance, requirements, contracts and decisions live in [`code-corhuila/dlc-docs`](https://github.com/code-corhuila/dlc-docs):

| Topic | Location in dlc-docs |
|---|---|
| Service definition | `09-microservices/services/01-api-gateway/` |
| Aggregate route contract | `07-api/contracts/openapi/api-gateway.yaml` |
| Authentication and session transport | `07-api/authentication.md` |
| Repository boundary | `09-microservices/transversal-repositories.md` |
| Communication patterns | `09-microservices/communication-patterns.md` |

## Status

Feature complete for HU-IAM-001 scope. Declarative NGINX configuration (Annex F). Delivered: `/health`, JSON access log, per-request DNS resolution, `404 NOT_FOUND` with the common envelope, `X-Correlation-Id` (reused or generated, returned and logged) and CORS limited to the `dlc-front` origin. Domain routes to the five owner services (`auth-service`, `patients-api`, `appointments-api`, `clinical-api`, `billing-api` on port 8080; `billing-api` is provisional until dlc-billing-api defines its compose service), the credential presence filter (`401 UNAUTHORIZED`), caller identity headers removed and `503 SERVICE_UNAVAILABLE` per route when a service is down. Rate limits per client IP: login 10 attempts in five minutes, general API 100 requests per minute with a burst of 50, both answering `429 TOO_MANY_REQUESTS` with `Retry-After`.

## Run locally

```bash
# With the owner services on the platform network
docker network create platform   # once, if it does not exist
docker compose -f deploy/compose.yml up -d --build

# Smoke tests against stand-in owner services (stops the IAM stand-in at the end)
docker compose -f tests/compose.smoke.yml up -d --build
GATEWAY_URL=http://localhost:18080 GATEWAY_CONTAINER=dlc-smoke-gateway \
  SMOKE_STUB_CONTAINER=dlc-smoke-patients-api SMOKE_STOP_CONTAINER=dlc-smoke-auth-service SMOKE_PROXY_URL=http://localhost:18081 bash tests/smoke.sh
docker compose -f tests/compose.smoke.yml down
```

## Branching

Permanent branches do not accept direct commits.

```text
develop  <--PR--  feat/... fix/... test/... chore/...
qa       <--PR--  promotion/qa-api-gateway-N
main     <--PR--  release/... hotfix/...
```

Promotion re-applies `develop` commits with `git cherry-pick -x`; permanent branches are never merged into each other. Changes to `main` require the teacher's approval. See `00-governance/branching-policy.md` in dlc-docs.
