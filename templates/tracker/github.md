# Ticket tracker: GitHub issues

`to-tickets` speaks three abstract verbs. This adapter is where they become commands.

## create-ticket

```sh
gh issue create --title "<title>" --body "<body>" --label ready-for-agent
```

One ticket per vertical slice, with its objective, its test-checkable done-when and
its blocking edges in the body. A slice that cannot be verified by a test is not a
ticket yet.

## list-ready

```sh
gh issue list --label ready-for-agent --state open
```

## close-ticket

```sh
gh issue close <number> --comment "closed by <commit or PR>"
```

Close it only with the evidence in the comment: the gate output, not a claim.
