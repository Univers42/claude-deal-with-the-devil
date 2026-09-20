---
paths:
  - "**/*.rs"
---

# Rust Refactoring

## Idioms

- Max 40 lines per function. Max 4 parameters; beyond that, a struct with a builder
  only if the builder earns its rung (`rules/minimalism-ladder.md`).
- Borrow by default. Take `&str` not `String`, `&[T]` not `Vec<T>`, and return owned
  values only when the caller needs ownership.
- `impl Trait` in argument position for simple generic bounds; a named generic when the
  caller must be able to name the type.
- Derive rather than implement: `Debug`, `Clone`, `PartialEq`, `Default` — hand-written
  versions drift from the fields.
- Newtypes over primitive obsession: `struct UserId(u64)` makes the wrong argument a
  compile error.
- Modules mirror the domain, not the layer. `pub(crate)` by default; `pub` is a
  contract (`rules/api-convention.md`).

## Errors are types, not strings

- Libraries define an error enum with `thiserror`; binaries use `anyhow` at the edge.
  Do not make a library return `anyhow::Error` — it erases the match.
- `?` for propagation. Never `.unwrap()` or `.expect()` on a path that can fail at
  runtime; in tests and in `main` they are fine, and `expect` there carries the reason.
- `panic!` means a bug in this code, never bad input from outside.
- No `unwrap_or_default()` where the default silently hides a failure.

## Ownership is the memory model — do not fight it

- **Do not hand-roll pools or arenas to satisfy the borrow checker.** A lifetime
  problem is a design problem; restructure the ownership first
  (`rules/dsa-and-memory.md`).
- Reach for `Rc`/`RefCell` only when the data genuinely has shared ownership, and
  `Arc`/`Mutex` only across threads. Each one is a rung; state why.
- An arena (`bumpalo`, `typed-arena`) is rung 6: only after a profiler shows allocation
  is the bottleneck.
- `clone()` is not a failure. An unnecessary clone in a hot loop is — and the profiler
  says which.

## Unsafe

- `unsafe` requires a `// SAFETY:` comment stating the invariant the caller must uphold
  and why it holds here. No comment, no `unsafe`.
- Keep the block as small as the operation. Wrap it in a safe API and test that API.
- `cargo miri test` on any module containing `unsafe`.

## Async

- Do not hold a `std::sync::Mutex` guard across an `.await` — use `tokio::sync::Mutex`
  or restructure so the lock is released first.
- No blocking IO inside an async fn; `spawn_blocking` for it.
- Every spawned task's `JoinHandle` is awaited or deliberately detached with a comment.
- Prefer structured concurrency (`JoinSet`, scoped tasks) over detached tasks nobody
  owns.

## After refactoring

- `cargo fmt --check` — clean.
- `cargo clippy --all-targets --all-features -- -D warnings` — zero. Consider
  `-W clippy::pedantic` and silence individually with a reason.
- `cargo test` and `cargo test --release` (debug assertions hide overflow panics).
- `cargo audit` / `cargo deny check` — no known-vuln dependency (`rules/quality-bar.md`).
- `#![deny(missing_docs)]` on a published crate; doctests count as tests and run in CI.

## Rust-specific ladder notes

- Rung 2: `std::iter` chains, `slice::binary_search`, `entry()` API — before any crate.
- Rung 4: the project already has `serde`/`tokio`/`regex`? Use it. A second
  serialization or runtime crate is a fork in the codebase.
- Rung 7: a trait with one implementor is not an abstraction, it is indirection. Delete
  it and call the type.
- `#[allow(...)]` carries an issue link and a one-line reason, like any suppression.
