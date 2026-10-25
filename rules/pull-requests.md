# Pull requests — understood in five seconds

*What a PR must say so a reviewer gets the change from its title and first line, and
what to do when it is not ready to be read.*

A reviewer gives a PR five seconds before deciding how to read it. The title and the
first line of the body spend them. Everything below is for the reviewer who decided
to keep reading. A PR that needs its diff to be understood is not done.

## The five seconds

- **Title** is the change, Conventional style: `feat(auth): refresh tokens before expiry`.
  Not the branch name, not "fixes".
- **First line** is the why in one sentence: the problem and who hits it.
- **One concern per PR.** If the summary needs "and", it is two PRs (`commit-craft`).

## The body, in this order

1. **Why** — the problem, with the evidence that it is real (issue, log, measurement).
2. **What changed** — a list a reviewer can check against the diff.
3. **Structure** — when boundaries moved: before → after, as a `mermaid` diagram or
   two lines. Name what was split, merged or moved, and why that shape.
4. **Trade-offs** — what this gives up, and the alternative rejected with its reason.
5. **Openings** (features) — what this makes cheap next, and what it deliberately
   does not do.
6. **Evidence** — test command and its result; numbers with the command that
   reproduces them; the source, paper or math that decided a constant or algorithm.
7. **Visible change → before/after.** Anything a user can see ships a screenshot or
   short recording of both states (`browser-testing` captures them). No media, no
   review.

Omit a section that is empty rather than writing "N/A". Never omit Why.

## Not ready to read yet

Open it as a **draft**: `gh pr create --draft`, then `gh pr ready` when it meets this
rule. GitLab: a `Draft:` title prefix. A draft needs no CI and can't be merged, so
it works on a repo with no tests.

Never mark not-ready by breaking tests on purpose. A red build that lies trains
everyone to ignore red, and on a repo with no CI it signals nothing. Where drafts don't
exist: `WIP:` title prefix and a `do-not-merge` label.

## Before you mark it ready

Re-read the title and first line as a stranger would. If they don't tell you what
changed and why, fix the words before asking for review.
