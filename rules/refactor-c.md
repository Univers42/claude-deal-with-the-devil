---
paths:
  - "**/*.c"
  - "**/*.h"
---

# C Refactoring

## Structure

- Max 40 lines per function (25 under the 42 Norm — see `agents/norminette.md`).
- Max 4 parameters; beyond that pass a `struct`.
- One translation unit per concern. A `.c` over 300 lines is at least two modules.
- `static` everything not in the header. The header is the public surface; keep it small.
- Include-guard every header. Include what you use, nothing more, and never a `.c`.
- No function bodies in headers except a deliberate `static inline`.

## Memory — every allocation has an owner and a free path

- The function that allocates documents who frees. Ownership transfer is stated in the
  header comment, not inferred.
- Every error path frees what it allocated before returning. This is where leaks live:
  the happy path is usually fine.
- `free()` then set the pointer to `NULL` when the variable outlives the call — a
  double-free is worse than a leak.
- Prefer one arena or pool for many short-lived allocations over N `malloc`/`free`
  pairs (`rules/dsa-and-memory.md`).
- Check **every** allocation for `NULL`. `malloc` returning `NULL` and being
  dereferenced three frames later is the classic C crash.

## Safety

- No unbounded string functions: `strcpy`, `strcat`, `sprintf`, `gets` — ever.
  Use the `n` variants and terminate explicitly; `snprintf` returns what it *would*
  have written, so check it against the buffer size.
- Bound every index. An attacker-controlled length is a size, not a promise.
- No implicit `int`. No implicit conversions between signed and unsigned in a
  comparison — `-Wsign-compare` exists because this silently inverts conditions.
- Integer overflow before an allocation is a vulnerability: check `n > SIZE_MAX / size`
  before `malloc(n * size)`.
- Initialize every variable. `-Wuninitialized` is not optional.

## Error handling

- One return convention per module and state it: `0`/`-1`, or a negative `errno`, or a
  result struct. Mixing them across a codebase is how errors get dropped.
- No silent swallow. Log, propagate or convert — never ignore.
- `goto cleanup` for multi-stage teardown is idiomatic C and correct here; the 42 Norm
  forbids it, so under the Norm use nested-free or a single-exit helper instead.

## Types and constants

- `const` everything that does not change, including pointer targets.
- `size_t` for sizes and indices; fixed-width `int32_t`/`uint64_t` when the width
  matters on the wire or on disk.
- No magic numbers. A named constant or an `enum`, never a bare literal in logic.
- `typedef` a struct only when the caller should not see inside it.

## After refactoring

- `gcc -Wall -Wextra -Werror -pedantic` — zero output. Add `-Wshadow -Wconversion`
  where the codebase can take it.
- `valgrind --leak-check=full --show-leak-kinds=all --error-exitcode=1` — zero leaks,
  zero invalid reads/writes.
- `-fsanitize=address,undefined` on the test build. ASan finds what valgrind misses
  on stack and globals, and UBSan finds the overflow that "worked".
- `cppcheck --enable=all` and `clang-format --dry-run --Werror`.
- For a 42 project: `norminette` clean (`agents/norminette.md`) — and check the
  subject's allowed-functions list, which no linter enforces.

## C-specific ladder notes

- Rung 2 is `string.h`, `stdlib.h`, `ctype.h` — reach for libc before writing a parser.
- Rung 3 is the platform: `mmap` over a read loop for a whole file, `epoll`/`kqueue`
  over a poll loop, a pipe over a shared buffer with a lock.
- Do not build a generic container with `void *` and function pointers for one type.
  That is rung 7 with one implementation (`rules/minimalism-ladder.md`).
