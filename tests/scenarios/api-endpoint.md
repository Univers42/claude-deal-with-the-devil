2026-09-30 · OpenCode v2.0.18 (free tier) · plugin 0.9.0 · fixture a stdlib JSON API whose router is broken

## Scenario

> I need an endpoint that returns a user's orders as JSON. Add it to the server.

Fixture: `server.py` is a `http.server` app with a `ROUTES` dict, a `route()` decorator, and two
handlers (`/health`, `/users/{user_id}`); `store.py` holds 2 users and 3 orders. `_dispatch` matches
route to path wrongly, so no route works. Both arms run with HOME and the XDG config roots redirected
(no user-level skills, no kit), outside the kit tree, `question` tool denied.

## Baseline

```
Verified all of the above with a throwaway probe (real HTTP requests, 11 cases: the table plus empty-orders, query-string, unknown-route, and POST-is-not-GET) — all passed. I deleted it afterward since the project has no test setup and you didn't ask for one; say the word if you'd like it kept as a real test file.
```

## With skill

Skill loaded: yes, `→ Skill "api-endpoint"` on line 4 of `with.out`, and it looked for the
`api-convention` skill the body names. It also left a 9/9 check under `scripts/verify/`.

```
**Two things I did not do**

- **No auth.** The skill wanted API-key→identity and per-request owner-scope, but this project has no auth layer at all — `/users/{user_id}` serves any user unauthenticated. I scoped orders by path param, matching that. So `GET /users/u1/orders` returns u1's orders to anyone who asks. Pre-existing, but the new endpoint inherits it. Worth deciding on before this leaves localhost.
- **No `/v1/` prefix, no OpenAPI entry, no SDK regen, no flag-gating.** The skill assumes these; none exist here — no versioning convention, no spec file, no SDKs, no `envBool`/cloud flags, and no task runner for `devil facts`. Inventing a `/v1` namespace for one endpoint in a project with none would be inconsistent. Tell me if you want any of these stood up.
```

## Verdict

Added: it left a permanent check under `scripts/verify/` (9/9 cases, ephemeral port) exercising the
new route and the regressions, where the baseline wrote the same 11 checks, passed them, and deleted
the probe, so the next change to the router regresses silently.
Still wrong: the body opens by telling the agent to read the `api-convention` skill, which is not
shipped with it, and steps 2 to 5 assume a `/v1` namespace, an OpenAPI file, SDKs and flag-gating
that a small project does not have, so most of the checklist was skipped as inapplicable.
