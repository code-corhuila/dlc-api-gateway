## User Story

Reference the corresponding user story or project issue.

Example:

`code-corhuila/dlc-docs#XX`

---

## What changes and why

Describe briefly:

- what this Pull Request changes;
- why the change is necessary;
- which Gateway responsibility it addresses (routing, credential presence, correlation, CORS, rate limit or its own errors).

---

## How it was tested

Describe the tests executed and the result of the `ci.yml` workflow.

Example:

```text
docker compose -f tests/compose.smoke.yml up -d --build && tests/smoke.sh
```

---

## Promotion trace

Complete this section only when promoting changes to `qa` or `main`.

Include the commits re-applied with:

```text
(cherry picked from commit <sha>)
```

Not applicable for normal development Pull Requests into `develop`.

---

## Checklist

- [ ] The change stays within the Gateway: configuration only, no business rules, no datastore.
- [ ] The Gateway does not validate tokens; owner services do (Annex F).
- [ ] Caller-supplied identity headers are removed and `/internal/v1` is never routed.
- [ ] Upstreams use a variable in `proxy_pass` so a stopped service only fails its own route.
- [ ] No secrets, tokens, private keys, or real `.env` files are committed.
- [ ] No credentials, cookies or request bodies are logged.
- [ ] Routes remain aligned with `07-api/contracts/openapi/api-gateway.yaml` in `dlc-docs`.
- [ ] `nginx -t` and `tests/smoke.sh` pass.
- [ ] The Pull Request references its corresponding user story or task.
