# Ticket tracker: GitLab issues

`to-tickets` speaks three abstract verbs. This adapter is where they become commands.

## create-ticket

```sh
glab issue create --title "<title>" --description "<body>" --label ready-for-agent
```

UNVERIFIED: no `glab` on the machine this kit was written on, so these flags were
not read off `glab issue create --help`. Check them once before the first publish.
The label has to exist in the project first (`glab label create ready-for-agent`);
GitLab rejects a label it does not have, and a fresh project has none.

One ticket per vertical slice, with its objective, its test-checkable done-when and
its blocking edges in the body. A slice that cannot be verified by a test is not a
ticket yet. The body shape is `templates/ticket.md`; this adapter only decides
how the body is delivered.

## list-ready

```sh
glab issue list --label ready-for-agent
```

UNVERIFIED: not read off `glab issue list --help` either. GitLab has no `ready`
label convention of its own; the label is this kit's, the same string the
`create-ticket` verb writes.

## close-ticket

```sh
glab issue note <iid> "closed by <commit or PR>: <gate output>"
glab issue close <iid>
```

UNVERIFIED: not read off `glab issue note --help` or `glab issue close --help`.
The note comes first because a closed issue is a poor place to leave the evidence.
GitLab addresses an issue by its project-local `iid`, which is not the GitHub
number: read it off `glab issue list` rather than assuming it matches.

Close it only with the evidence in the note: the gate output, not a claim.

Caveat: `glab issue list --label` filters on the label and prints the state in a
column, so a closed or merged issue that still carries `ready-for-agent` can show
up in the ready list. Check the state column before starting a slice. Unlike
`gh issue list --state open`, the label filter alone is not an open filter, and
that difference is the one this adapter cannot paper over.
