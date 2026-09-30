2026-09-30 · OpenCode 2.0.18 (free tier) · plugin 0.9.0 · fixture a static signup page plus a stdlib server answering POST /api/signup

## Scenario

> can you actually open the signup page in a browser, submit the form, and tell me
> what happens and what the console says?

`index.html`, `styles.css`, `app.js` and `serve.py`: a one-field form that posts to
`/api/signup` (201), then reveals a confirmation. `app.js:12` reads
`form.elements.mail.value` where the field is named `email`, so it throws before
`fetch`. No test runner, no Playwright, no Node. Both arms hit
`[browser.disconnected]`, so this RED is weaker than intended: the baseline
reached the same diagnosis from the source, so what is measured is the evidence,
not the conclusion. Re-record with a browser attached.

## Baseline

```
I couldn't do the browser part: the desktop browser isn't connected to this session. `browser.tabs.list` returns `[browser.disconnected]`, and the tool explicitly says retrying while disconnected won't help. So I have no real observations of the page or its console.

What I can report is from reading the fixture, not from running it. In `/tmp/opencode/scen/browser-testing/base/app.js`:

const email = form.elements.mail.value;

`index.html:14` declares the input as `name="email"`, so `form.elements.mail` is `undefined` and `.value` throws a `TypeError` inside the submit handler. Consequences:
- Nothing reaches `POST /api/signup` — the throw happens before the `fetch` on line 16.
- `done.hidden = false` on line 26 never runs, so `#done` stays hidden. The form just looks like a dead button.
```

## With skill

Skill loaded: yes, `→ Skill "browser-testing"` on line 4 of the run.

````
[...the setup note, in which it falls back from the disconnected `browser` tool to the Chromium binary over CDP, is elided...]

**Nothing visible. The button is dead.** No confirmation, no error, no navigation — the page looks identical before and after.

![after submit](/tmp/opencode/signup-after-submit.png)

[...the "## What the console says" heading is elided...]

```
[UNCAUGHT] TypeError: Cannot read properties of undefined (reading 'value')
    at HTMLFormElement.<anonymous> (http://127.0.0.1:8765/app.js:12:36)
            at http://127.0.0.1:8765/app.js:11:35

[log:error] Failed to load resource: 404 (File not found) — /favicon.ico
```

**No request ever leaves the page.** The CDP network log shows only the three GETs for `index.html`, `styles.css`, `app.js` — there is no `POST /api/signup`. I confirmed this two independent ways:
````

## Verdict

Added: the skill's "read the console and the network" step turned a correct
guess into evidence, so the run reports the uncaught `TypeError` with its stack, a
before/after screenshot, and a two-source negative (CDP and the server's own log)
that no `POST /api/signup` ever left; step 5 also closed the server and the port.
Still wrong: step 4 never happened, so the reproduction left no regression spec,
and the run stayed at one viewport in one theme with no keyboard or axe pass.