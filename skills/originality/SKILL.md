---
name: originality
description: >
  Prior-art pass before writing something new — find what already does this, in the repo
  and outside it, then say plainly whether to reuse, wrap, or build and why.
  Auto-triggers on: "has this been done", "is there a library for", "should I build this",
  "prior art", "am I reinventing", "write a X from scratch"
allowed-tools: Read, Grep, Glob, Bash, WebSearch, WebFetch
---

# Originality

Original does not mean unprecedented; it means *knowing what exists and being
deliberate about differing from it*. The expensive mistake is the fourth in-house
implementation of something the stdlib has had since 2019 — written confidently,
because nobody looked.

This is `library-first` extended past the repo boundary. Ten minutes here routinely
deletes a week.

## 1. Search inward first — the cheapest win

```sh
.claude/tools/codemap.sh          # where a symbol already lives
.claude/tools/dupes.sh            # blocks already repeated
.claude/tools/facts.sh            # what the project already scripts
.claude/tools/scripts.sh list     # the vetted external script registry
rg -i '<the concept, and its synonyms>'
```

Search **behaviour, not your chosen name**. The existing implementation is called
`normalize`, you were going to call it `sanitize`, and that is why you did not find it.
Try three names.

Check the dependency manifest too. The project very likely already pulls in a date
library, a validator, a fetch wrapper, a retry helper — rung 4 of
`rules/minimalism-ladder.md`.

## 2. Search outward — the ladder, in order

1. **The standard library.** Check it properly. `itertools`, `slices`, `Intl`,
   `<algorithm>`, `functools`, coreutils. Most "utility" code is a stdlib call with a
   different name.
2. **The platform.** The OS, the database, the HTTP layer, the runtime. A unique index
   beats an application-level duplicate check. `cron` beats a scheduler.
3. **The ecosystem.** `WebSearch` for the problem in the language's own vocabulary. Read
   the top issue list, not just the README.

## 3. Judge what you found — on evidence

For each real candidate:

| Question | Why it decides |
|---|---|
| Maintained? Last release, open-issue trend | An abandoned dependency is future work you have not scheduled |
| What does it pull in? | A transitive tree is the real cost (`rules/quality-bar.md` layer 5) |
| Licence compatible? | Not optional, and easy to check |
| How much of it do you need? | Using 5% of a large library is a rung-5 helper wearing a dependency |
| How hard is it to remove? | A library at the core is a decision; at the edge it is a choice |

## 4. Decide, and say which

Exactly one of:

- **Reuse** — it does the job. Use it. Say which version and why it is safe.
- **Wrap** — it does the job behind an interface you control, so swapping it later is
  cheap. Correct when it is load-bearing but replaceable.
- **Borrow the idea** — the approach is right, the dependency is not (too big, wrong
  licence, unmaintained). Implement the idea, **credit the source**, and say what you
  left out.
- **Build** — nothing fits, and you can name what is genuinely different about this
  case. This is the answer that needs the most evidence, not the least.

"Build" without the search is not originality, it is ignorance with good posture.
"Reuse" without reading the code is a supply-chain decision made by accident.

## 5. Be honest about what is actually new

When something genuinely is novel here, say what and why — the constraint nobody else
had, the combination nobody tried. And when it is not, say that too. A wrapper described
as an innovation costs you credibility you will want later.

## Report

- **Searched:** the terms used, inward and outward. Someone will re-run them.
- **Found:** the candidates, with maintenance and dependency facts.
- **Decision:** reuse / wrap / borrow / build, in one line, with the reason.
- **If build:** what is different about this case that made every candidate wrong.
- **If borrow:** the source, credited, and what you deliberately left out.
