---
paths:
  - "**/routes/**"
  - "**/handlers/**"
  - "**/controllers/**"
  - "**/api/**"
  - "**/*router*"
  - "**/*controller*"
---

# API Conventions

*REST API conventions — endpoints, auth, access control, errors.*

## Shape

- Resource-oriented, plural-noun paths under a version prefix (`/v1/<resource>`).
- Versioned — never break a shipped contract; add, don't mutate.
- JSON in/out; document every public route in the project's OpenAPI / API spec.

## Auth & access control

- Authenticate every request; resolve the caller's identity from the credential, not from a path `{id}`.
- Authorize per request — scope every read and write to the caller; never trust client-supplied ownership.
- No cross-owner access by construction — derive the owner from the credential, not the request body.

## Errors

- Correct HTTP status: 400 bad input, 401 unauthenticated, 403 denied, 404 not-found, 409 conflict, 429 rate-limit.
- One consistent error envelope; never leak internals (stack traces, SQL, DSNs, file paths) in the body.
- Actionable: what failed, why, what the caller can do.

## Pagination & idempotency

- List endpoints paginate by default (cursor or limit/offset) — never return an unbounded set.
- Mutations are idempotent where the verb implies it (`PUT`/`DELETE`); accept an idempotency key for unsafe retries.

## Flag-gating (when applicable)

- New or risky behavior mounts behind a flag (default off) — a missing flag means the old behavior, unchanged.

## After changes

- Update the OpenAPI spec and regenerate any SDKs.
- Add or extend the project's verification gate (a `scripts/verify/` check or CI job).
