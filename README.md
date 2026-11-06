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

Not started. Gateway technology, ports, health routes, environment keys and the generic rate limit remain pending decisions.

## Branching

Permanent branches do not accept direct commits.

```text
develop  <--PR--  feat/... fix/... test/... chore/...
qa       <--PR--  promotion/qa-api-gateway-N
main     <--PR--  release/... hotfix/...
```

Promotion re-applies `develop` commits with `git cherry-pick -x`; permanent branches are never merged into each other. Changes to `main` require the teacher's approval. See `00-governance/branching-policy.md` in dlc-docs.
