# Ticket tracker: GitLab issues

`to-tickets` speaks three abstract verbs. This adapter is where they become commands.
`wayfinder` speaks five more, below.

Every command here was checked against `glab` 1.120.0: its `--help`, and its source
where the help is silent. GitLab addresses an issue by its project-local `iid`, which
is not a GitHub number: read it off `glab issue list` rather than assuming it matches.

GitLab refuses a label the project does not have, and a fresh project has none, so
create the three this adapter writes once per project:

```sh
glab label create --name ready-for-agent
glab label create --name wayfinder
glab label create --name wayfinder:map
```

## create-ticket

```sh
glab issue create --title "<title>" --description "<body>" --label ready-for-agent
```

One ticket per vertical slice, with its objective, its test-checkable done-when and
its blocking edges in the body. A slice that cannot be verified by a test is not a
ticket yet. The body shape is `templates/ticket.md`; this adapter only decides
how the body is delivered.

## list-ready

```sh
glab issue list --label ready-for-agent
```

`glab issue list` lists open issues unless `--closed` or `--all` is passed, so the
label is the only filter this needs.

## close-ticket

```sh
glab issue note <iid> --message "closed by <commit or PR>: <gate output>"
glab issue close <iid>
```

The note comes first because a closed issue is a poor place to leave the evidence.
`glab issue note` takes exactly one argument, the `iid`: the text goes in
`--message`, and without it glab opens an editor.

Close it only with the evidence in the note: the gate output, not a claim.

## Wayfinding operations

The map is one issue and its tickets are the rest, so a session's claim and its
resolution are visible in the tracker's own UI: nobody has to open the map to see
what another session took.

A wayfinding ticket is created with the `create-ticket` command, carrying
`--label wayfinder` in place of `--label ready-for-agent`. It is a decision, not a
build slice, so `list-ready` must not offer it, and `list-tickets` finds it by that
label.

### create-map

```sh
glab issue create --title "<destination, as a title>" --description-file <map> --label wayfinder:map
```

The map body is `templates/wayfinder-map.md`, filled in.

### read-map

```sh
glab issue view <iid> --comments
```

### list-tickets

```sh
glab issue list --label wayfinder
```

Caveat: a ticket's blockers are the `Blocks` line in its body. GitLab's native
blocking link is a paid-tier feature with no `glab issue` command, so the frontier
is read from text and a ticket whose blocker was never wired reads as ready. Wire
the edges when the tickets are created.

### claim-ticket

```sh
glab issue update <iid> --assignee "+@me"
```

The `+` adds an assignee instead of replacing the ones already there, and glab
resolves `@me` to the signed-in user. The assignee is the claim, which is why it
happens before any work and not after.

### close-ticket

```sh
glab issue note <iid> --message "<the answer, then the evidence>"
glab issue close <iid>
```
