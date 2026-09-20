# Minimalism ladder — climb only as high as you must

*Start at the bottom rung and stop the moment the problem is solved.*

Most bloat is someone starting three rungs too high because the higher rung felt more
professional. `dsa-and-memory.md` decides WHAT structure to reach for; this decides how
much machinery is allowed to exist at all.

## The rungs

0. **YAGNI — don't build it.** Does this solve a problem that exists *now*, for a caller
   that exists *now*? This rung eliminates more code than all the others combined.
1. **Delete instead.** Can the need disappear if something upstream is simplified? The
   best change removes a copy and adds a call.
2. **The standard library.** Before any import: does the language already ship this?
3. **The platform.** The OS, database, runtime or HTTP layer. A unique index beats an
   application-level duplicate check; `cron` beats a scheduler.
4. **A dependency already in the manifest.** A second library for the same job is worse
   than the slightly-wrong first one.
5. **A one-liner or a small helper.** Twenty lines you own beat a transitive tree you
   don't — name the concern and put it in the library (`rules/library-first.md`).
6. **A new dependency.** Only with the accounting written down: what it pulls in, who
   maintains it, what the removal path is.
7. **A new abstraction.** Requires **three** real implementations, not two and an
   imagined one.

## The performance override

The ladder loses to a measurement, and only to a measurement. A lower rung that is a
**worse complexity class on data that grows** is the slow choice, not the simple one —
take the better algorithm. On a **hot path**, a profiled number wins; "hot" means a
profiler said so. Everywhere else, simple wins: an optimisation without a benchmark is a
complication, and under 3% is noise (`agents/benchmarker.md`).

## Signs you climbed too high

An interface with one implementation · a factory constructing one type · a config knob
nobody sets · a wrapper that only forwards · a generic parameter instantiated once · a
plugin API with one plugin · "we'll need this when…" next to code running today.

Each is a deletion, not a refactor.

## State the rung

A change landing on rung 5 or higher says which rung and why the one below it failed —
one line, in the commit. A rung climbed without a stated reason was climbed by accident.

The `originality` skill runs rungs 2–4 properly (prior art, inward and outward);
`brainstorm` forces the range that keeps rung 0 on the table.
