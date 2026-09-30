# Ticket tracker: GitHub issues

`to-tickets` speaks three abstract verbs. This adapter is where they become commands.
`wayfinder` speaks five more, below.

## create-ticket

```sh
gh issue create --title "<title>" --body "<body>" --label ready-for-agent
```

One ticket per vertical slice, with its objective, its test-checkable done-when and
its blocking edges in the body. A slice that cannot be verified by a test is not a
ticket yet. The body shape is `templates/ticket.md`; this adapter only decides
how the body is delivered.

## list-ready

```sh
gh issue list --label ready-for-agent --state open
```

## close-ticket

```sh
gh issue close <number> --comment "closed by <commit or PR>"
```

Close it only with the evidence in the comment: the gate output, not a claim.

## Wayfinding operations

The map is one issue and its tickets are the rest, so a session's claim and its
resolution are visible in the tracker's own UI: nobody has to open the map to see
what another session took.

## create-map

```sh
gh issue create --title "<destination, as a title>" --body-file <map> --label wayfinder:map
```

The map body is `templates/wayfinder-map.md`, filled in.

## read-map

```sh
gh issue view <number>
```

## list-tickets

```sh
gh issue list --label wayfinder --state open
```

Caveat: a ticket's blockers are the `Blocks` line in its body, not a native
dependency link, so the frontier is read from text and a ticket whose blocker was
never wired reads as ready. Wire the edges when the tickets are created.

## claim-ticket

```sh
gh issue edit <number> --add-assignee "@me"
```

The assignee is the claim, which is why it happens before any work and not after.

## close-ticket

```sh
gh issue close <number> --comment "<the answer, then the evidence>"
```
