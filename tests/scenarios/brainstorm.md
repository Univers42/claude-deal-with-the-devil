2026-09-30 · OpenCode v2.0.18 (free tier) · plugin 0.9.0 · fixture `storefacts`, stdlib-only append-only store, one JSON file per fact

## Scenario

> Our fact store writes one JSON file per fact, so `facts/` grows forever and listing it is getting slow. Before I touch anything, I want to understand what the options are for storing and indexing these. What are our options, and what would you actually do? I am not asking you to implement it yet.

Fixture: `README.md`, `src/store.py` (tmp+rename append), `src/list.py` (glob + sort, reads
every file). The two rough edges named in the README are latency and unbounded growth. No
tests, no dependency manifest, so the design is genuinely open.

## Baseline

Excerpt from `base.out` (no skill loaded):

```text
| files | `glob+sort` | `list.py` read-all (warm) |
| 25,000 | 0.141s | — |
| 50,000 | 0.329s | 0.769s |
| 100,000 | 0.775s | — |
| 200,000 | 1.630s | — |
...
**Sharded JSONL** — you trade the directory entry per fact for a directory entry per ~2000 facts.
**SQLite** — by far the best read numbers and the only option that gives you real queries
```

It benchmarked, produced four options, and named sharded JSONL as the pick. It has no
scoring table, no "do nothing" rung, and no kill criterion anywhere in the output.

## With skill

Skill loaded: `Skill "brainstorm"`. Excerpt from `with.out`:

```text
| Option | Impact | Conf | Cost | Reversibility | Score |
| **2** Fix key, keep files | 4 | 5 | 1 | full | **20.0** |
| **3** Shard by date | 4 | 5 | 2 | easy | **10.0** |
| **4** SQLite | 5 | 4 | 3 | staged | **6.7** |
...
Smallest experiment, signal, kill criterion:
- **Kill criterion:** if 100,000 facts still list in **under ~150 ms**, the perf argument
  for SQLite is **dead** — keep flat files, shard by date (option 3) if it ever gets
  uncomfortable
```

Nine options (rung 0 "do nothing" through DuckDB and "invert, no index"), the five-column
score table, and a kill criterion stated before any work.

## Verdict

Added: the skill's shape shows as a nine-option ladder with an explicit do-nothing rung,
a scored table, and a named kill criterion tied to a measurable number.
Still wrong: it split the recommendation into "fix the id now, SQLite on a trigger later"
and answered none of its own four blocking questions, so the headline pick is deferred.
