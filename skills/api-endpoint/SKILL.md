---
name: api-endpoint
description: >
  Scaffold a new REST endpoint across the planes. Auto-triggers on:
  "add an endpoint", "new API route", "expose this over HTTP", "wire a handler"
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# API Endpoint

DO NOT add a route before reading the nearest existing handler and `.claude/rules/api-convention.md`.

## 1. Locate

- Which part of the project owns it; find the closest existing endpoint.
- Mirror its file, registration, and owner-scoping pattern.

## 2. Design

- Method, path (`/v1/...`), request/response shape, auth (API-key → identity), per-request owner-scope.
- Cloud/enterprise behavior is flag-gated OFF (`if envBool("FLAG")`, default false).

## 3. Implement

- Handler + route registration + the entry in the project's OpenAPI / API spec.
- Adapter-agnostic: if it touches data, it must hold across every backend the project supports.

## 4. Verify

- Run the relevant check through the project's task runner (detect it with `.claude/tools/facts.sh`).
- Regenerate SDKs if the spec changed.
- Add a verify gate (a `scripts/verify/` check or CI job) that exercises the route.

## 5. Report

- Files changed, the new route + its auth/owner-scope, and the gate that proves it.
