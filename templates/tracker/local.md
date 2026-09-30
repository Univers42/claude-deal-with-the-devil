# Ticket tracker: local files

`to-tickets` speaks three abstract verbs. This adapter is where they become commands.
`wayfinder` speaks five more, below.

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

## Wayfinding operations

The map is a file too, and its tickets are files beside it, so a session's state
outlives the session without a network call.

## create-map

Write `.scratch/wayfinder/map.md`, filled in from `templates/wayfinder-map.md`.
That template owns the shape; this adapter only decides where the map lands.

## read-map

```sh
cat .scratch/wayfinder/map.md
```

## list-tickets

```sh
ls .scratch/wayfinder/tickets/
```

A ticket is ready when its `Blocks:` section names no open ticket. Caveat: there is
no lock here, so two sessions read the same frontier and one of them loses the
claim. Re-read the ticket before writing to it.

## claim-ticket

Add `- Claimed: <session>` under the ticket's `Question`. The claim is the line, so
it needs no mechanism behind it, which is also why it does not stop anyone.

## close-ticket

Append `## Closed <UTC date>` with the answer and the evidence. A ticket keeps its
question above that line: a closed ticket nobody can read is a loss, not a record.
