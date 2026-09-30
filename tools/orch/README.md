# `tools/orch/` — run headless OpenCode builders and check their work

Delegate bulk building to headless OpenCode jobs (one per git worktree), watch them with one
line per job, and never merge on an agent's say-so.

| Script | Does |
|---|---|
| `oc-run.sh <label> <worktree> <agent> <prompt>` | one headless `opencode run` in the worktree; journal in `<worktree>/target/wf/<label>.{jsonl,pid,rc,session-id,stderr}` |
| `oc-job.sh <label> <worktree> <agent> <body> [rows]` | prompt = `$OC_COMMON_PROMPT` + body; runs `oc-run.sh`; commits and pushes the branch only if the job exited 0, its return block says `status: done`, and the optional rows gate is green. Exit 0 ok · 1 gate red · 2 agent not done · 3 worktree already busy |
| `oc-status.sh [root]` | one line per job under `<root>/*/target/wf`: state (`RUNNING`, `done(rc=N)`, `DEAD`, `STALLED`), minutes since the last event, session id, last ~200 chars the model wrote |
| `gate.sh <logdir> <rows>` | rows `name\|expect\|cmd` (expect `0` or `nonzero`); one log per row and `<logdir>/summary.txt`; a row that could not run keeps its real exit code, never a pass |
| `timed <cmd...>` | run a long gate under a host-wide `flock`, one at a time |

## The loop

1. One branch and one worktree per unit of work; one agent per worktree (`oc-job.sh` exits 3 otherwise).
2. Launch in the background: `nohup tools/orch/oc-job.sh p9 ../wt/p9 builder body.txt rows.txt &`.
3. Watch: `tools/orch/oc-status.sh ../wt` (or `watch -n 20 …`). Open a session read-only with
   `opencode -s <session-id>` from its worktree; do not type into a running job.
4. On finish: merge the target branch into the job's branch, then run the gates **yourself**
   (format, lint, the full test suite). The agent's reported exit codes are a claim; your run
   decides the merge. A gate that did not run is not a pass.

## The return block

Every body (or `$OC_COMMON_PROMPT`) must require the agent to end with a block that
`oc-job.sh` can grep:

```text
status: done | partial | blocked
gates: fmt=<rc> lint=<rc> test=<rc>
changed: <files>
deviations: <anything outside the task's file list>
next: <the next step, if not done>
```

## Limits

- `STALLED` is judged by the journal's modification time (> `OC_STALL_MIN`, default 30 min): a
  model thinking silently for longer shows as stalled even if it is fine.
- `oc-run.sh`'s hard timeout (`OC_TIMEOUT`, default 4 h) also kills a slow but live job; resume
  with `opencode run --session <id>`.
- Without a rows file, `oc-job.sh` pushes on the agent's own `status: done`: gate before merging.
- `oc-job.sh`'s busy check reads `/proc/<pid>/cwd`: Linux only.
