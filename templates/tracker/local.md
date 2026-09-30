# Ticket tracker: local files

`to-tickets` speaks three abstract verbs. This adapter is where they become commands.

## create-ticket

Write `.scratch/tickets/NNN-slug.md`, NNN the next free number, filled in from
`templates/ticket.md`. That template owns the body shape; this adapter only
decides where the file lands.

## list-ready

```sh
ls .scratch/tickets/
```

A ticket is ready when its `Blocks:` section names no open ticket.

## close-ticket

Append `## Closed <date> by <commit>` to the file, with the gate output.
`.scratch/` is gitignored, so the record is local unless you copy it out.
