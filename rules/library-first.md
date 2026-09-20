# Library-first — extract before you duplicate

*Build a project-tailored library first; features are thin glue. No redundancy.*

The smallest, fastest codebase is the one where each capability exists once.
Before adding feature code, build the reusable primitive; the feature is then thin
glue over it.

## The discipline

- **Reuse before write.** A primitive that exists is used, not re-implemented.
  Search first (`rg`, the cached `codemap`) — assume it already exists.
- **Extract before the second copy.** The first time you would paste a block, stop:
  lift it into the library, test it once, call it twice.
- **The library is tested in isolation.** A primitive ships with its own test,
  independent of any caller. Callers trust it; they don't re-test it.
- **Features are glue.** A feature wires tested primitives together. If a feature
  function exceeds the tech line limit, a primitive is hiding inside it — extract it.

## Where the library lives

- One home per concern, named for behavior (`tokens/`, `pagination/` — not `utils/`).
- `utils` / `helpers` / `misc` are not a library, they are a junk drawer. Name the concern.
- Domain primitives carry zero infrastructure imports (see `agents/architect.md`).

## Find the redundancy with tools, not eyes

- `.claude/tools/dupes.sh` lists repeated blocks — each is an extraction candidate.
- `.claude/tools/codemap.sh` shows where a symbol already lives before you add another.
- Run them; act on them. A duplication candidate left in place is a decision to
  maintain two copies forever.

## The bar

- Two functions that change for the same reason are one function in the wrong place.
- Deletion beats addition — the best change removes a copy and adds a call.
- Nothing is lost, everything transforms: every block worth pasting is worth a name.
