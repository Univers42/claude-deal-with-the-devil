---
paths:
  - "**/*.go"
---

# Go Refactoring

## Idioms

- Max 40 lines per function
- Accept interfaces, return structs
- Errors are values — handle them, don't panic
- No init() unless absolutely forced by a dependency
- No globals — inject dependencies
- Receiver name: one or two letters, consistent across methods
- Context is always the first parameter

## Hexagonal architecture

- Ports (interfaces) in the domain package
- Adapters implement ports, never imported by domain
- No infrastructure types in domain signatures

## After refactoring

- `go vet ./...` — zero issues
- `golangci-lint run` — zero issues
- `go test -race ./...` — zero failures
- Check goroutine leaks with goleak in tests

## Go-specific ladder extensions

- Rung 2: `strings`, `strconv`, `slices`, `maps` before any import.
- Rung 3: `net/http` before gin/chi/echo; `database/sql` before an ORM.
- Rung 4: a stdlib interface fits (`io.Reader`, `fmt.Stringer`)? Use it — don't define your own.
- No constructor function if the zero value is usable.
- No getter/setter if the field can be public.

## Go performance guardrails

- Ladder says "stdlib" but:
  - `fmt.Sprintf` for string building in a loop? `strings.Builder`.
  - `json.Marshal` per request? A pre-compiled codec (easyjson, sonic).
  - `regexp.MatchString` per request? Compile once at init.
  - `http.Get` convenience? Reuse an `http.Client` with connection pooling.
- Ladder says "one-liner" but:
  - `append()` in a hot loop without a pre-sized slice? `make([]T, 0, n)`.
  - map access in a hot loop? A slice if keys are dense integers.
  - `interface{}` on a hot path? A concrete type avoids boxing allocation.
- `sync.Pool` for high-churn allocations (byte buffers, request objects).
- Avoid `reflect` on hot paths — it allocates on every call.
- Channel vs mutex: mutex to protect-and-release, channel for hand-off.
