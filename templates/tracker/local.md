# Ticket tracker: local files

`to-tickets` speaks three abstract verbs. This adapter is where they become commands.

## create-ticket

Write `.scratch/tickets/NNN-slug.md`, NNN the next free number:

```md
# NNN <slug>
Objective: <one slice, end to end>
Done when: <a command a test can run>
Blocks: NNN, NNN
```

## list-ready

```sh
ls .scratch/tickets/
```

A ticket is ready when its `Blocks:` list is empty, or names only closed tickets.

## close-ticket

Append `## Closed <date> by <commit>` to the file, with the gate output.
`.scratch/` is gitignored, so the record is local unless you copy it out.
