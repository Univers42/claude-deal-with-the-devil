# The user profile: one pinned `~/.claude` for every machine

`devil profile` brings the **user scope** (`~/.claude`, `~/.claude.json`, `~/.local/bin`) to
the profile in [`profiles/user.json`](../profiles/user.json). `devil setup` seeds a *repo*; this
seeds *you*. Re-run it on a new machine instead of re-explaining how you work.

```sh
devil profile                 # dry run: what would change
devil profile --check         # exit 1 if anything drifted, 2 if a stage cannot run
devil profile --apply         # install, enable, write; idempotent
devil profile --apply --pack frontend --only plugins
```

What it does not do:

- It never removes a plugin, a marketplace or an MCP server that the profile does not name.
- It never overwrites a skill directory it did not vendor itself.
- It never puts a secret in the repo.

Machine-specific values live in the private overlay `~/.config/harness42/local.json`
(template: [`profiles/local.example.json`](../profiles/local.example.json), `chmod 600`). An MCP
server that needs a value the overlay lacks is skipped and named in the report.

## Local only and free: nothing from the claude.ai account, no paid MCP

No MCP server that needs a paid plan or a cloud account. When a local option exists, it is the one
taken (user decision, 2026-10-31). The `localonly` stage enforces the cloud half. The paid half is
a review rule: check a service's pricing and auth before adding it.

Rule (2026-10-31): everything is declared here and runs on this machine. The profile sets, in
`~/.claude/settings.json`:

- `ENABLE_CLAUDEAI_MCP_SERVERS=false`: no connector from the claude.ai account loads.
- `syncClaudeAiPlugins: false`: no plugin syncs down from claude.ai.

The login itself is untouched.

No plugin that bundles a remote MCP server is installed. Those plugins sit in `remove_plugins`, and
an apply uninstalls them:

- context7, figma, github and fly, which reach hosted services;
- mongodb, whose bundled server is unpinned;
- the knowledge-work-plugins, which bundle more than 50 SaaS connectors (Slack, Notion, Stripe, Gmail…).

To use a cloud service from another account later, add its plugin to that machine's profile
deliberately. The history of this file shows which ones existed.

## Stages

| Stage | Brings | How it decides |
|---|---|---|
| tools | uv, bun, rust-analyzer, codebase-memory-mcp, LSP servers, ccusage, specify, serena into `~/.local/bin` | each tool's own `--version`. Archives are sha256-verified before install |
| marketplaces | the plugin catalogs below | matched by name; never removed |
| plugins | every plugin of the selected packs, at user scope, enabled | `claude plugin list --json`. An LSP plugin whose server binary is missing is skipped |
| mcp | stdio servers with exact versions | `~/.claude.json`, compared field by field; a hand-edited server is restored |
| skills | single skills vendored from a pinned commit | a `.harness42` stamp in each directory |
| retire | loose skills that an installed plugin also ships | moved to `~/.claude/backups/skills-<date>/`, never deleted |
| settings | `env` keys, model and effort, theme, the claude.ai off-switches; then the overlay's `settings` (autoMode, which names your own infrastructure) | merged, overlay last; every other key in `settings.json` kept |
| instructions | the block in [`profiles/claude-md.md`](../profiles/claude-md.md) | between `harness42:profile` markers; your own text kept |
| budget | the always-on token cost of the profile's plugins | `claude plugin details`; fails `--check` above `budget.always_on_tokens` |
| lock | `profiles/user.lock.json`: installed version + commit per entry | written on `--apply`, compared otherwise. Commit it with the profile |

## Packs

Sources, in order of trust:

- **Tier A** is on Trail of Bits' approved-marketplace list: `anthropics/claude-plugins-official`,
  `anthropics/knowledge-work-plugins`, `trailofbits/*`, `obra/superpowers`.
- **Tier B** is vendor-official and pinned: shadcn, vercel-labs, bytebase, superfly, spf13,
  revfactory, thedotmack, DeusData, rtk-ai.
- The official Anthropic marketplace updates itself (Claude Code default), so its plugins float and
  the lock records what you got. Third-party marketplaces do not update unless pinned to a new `#ref`.

| Pack | What it adds | Leaves the machine |
|---|---|---|
| core | superpowers, devil (this kit: its hooks and gates in every project), claude-md-management, skill-creator, session-report, hookify, code-review, pr-review-toolkit, feature-dev, code-simplifier, claude-code-setup, ralph-loop, mattpocock-skills, harness (revfactory, "Harness v2": builds a project's agent team), Spec Kit CLI, agent-teams flag | nothing beyond Claude itself |
| knowledge | LSP plugins (typescript, gopls, rust-analyzer, pyright, clangd), codebase-memory-mcp (local code graph), serena, ccusage | nothing |
| frontend | frontend-design, ui-ux-pro-max, modern-web-guidance, playwright + chrome-devtools MCP (headless, isolated), shadcn MCP, vercel react/web-design skills, anthropics webapp-testing | nothing |
| backend | dbhub (read-only, 1000-row cap), redis-development, go (spf13), rust-review (ToB); `gh` and `fly` stay plain CLIs | nothing |
| business | 71 skills from knowledge-work-plugins (product, engineering, design, data, operations, marketing, finance, legal, brand-voice) **vendored without their plugins**, so none of their connectors loads; anthropics docx / pdf / pptx / xlsx / doc-coauthoring | nothing |
| security | security-guidance, claude-security (official); ToB insecure-defaults, differential-review, supply-chain-risk-auditor, property-based-testing, testing-handbook-skills, semgrep-rule-creator, audit-context-building, agentic-actions-auditor, static-analysis; skills-curated threat-model, security-best-practices, ownership-map, security-awareness, ffuf-web-fuzzing; Semgrep CE CLI 1.183.0 | nothing. The hooks were read before adoption: none makes a network call. security-guidance keeps a local Agent SDK venv |
| memory | claude-mem v15.7.0 (local SQLite + Chroma, compression on your Claude plan, worker on 127.0.0.1); rtk 1.1.0 OSS build (a PreToolUse Bash hook that compresses command output) | nothing. claude-mem telemetry is off in three layers: `DO_NOT_TRACK`, `CLAUDE_MEM_TELEMETRY=off`, `telemetry.json`. rtk telemetry consent is `no` |
| orchestrator | n8n 2.45.7 on the host from a committed lockfile (`profiles/n8n/`), a systemd user unit on 127.0.0.1:5678, a starter workflow (`claude -p` with an explicit `--allowedTools`), and a nightly systemd timer running `devil profile --check` into `~/.cache/harness42/reports/` | nothing. Diagnostics, templates, version checks and community packages are off |

Not installed, and why:

- **official semgrep plugin:** a binary hook on every Write/Edit/Bash, plus a hosted MCP. The Semgrep CE CLI and `devil quality` cover it locally.
- **ToB fp-check:** an LLM prompt-hook on every Stop, even when the skill is unused.
- **DAP debugger MCPs:** ctagard/dap-mcp (11★) and Govinda-Fichtner/debugger-mcp (6★) are too young to trust.

- **Hooks on every tool call, or a competing methodology:** ruflo, oh-my-claudecode, ECC, GSD, gstack,
  SuperClaude, BMAD, compound-engineering.
- **Sends code to the cloud or needs a paid plan:** claude-context, mem0, 21st Magic, axe, superdesign,
  Supermemory cloud.
- **Rewrites every reply:** explanatory / learning output styles.
- **Adds an attribution trailer, against the no-co-author rule:** commit-commands.
- **Not this stack:** kubernetes, Next/Vite devtools, vercel, supabase, prisma.
- **Duplicate subagent catalogs without tags to pin:** wshobson/agents, VoltAgent.

## Sovereignty, measured: `devil sovereign`

The settings above are promises; `devil sovereign` checks what the machine does. Three of the
promises broke during this build: claude-mem's telemetry defaulted on, `InaccessiblePaths=` was
skipped silently, and a claude.ai connector loaded despite its off-switch. It checks:

- the claude.ai switches and `DO_NOT_TRACK`;
- that no user or project MCP server in `~/.claude.json` is a remote URL;
- that none of your processes listens beyond loopback (`ss -ltnp`);
- that no process of a `harness42-*` unit can read `~/.ssh`, `~/.gnupg` or `~/.config/gh`,
  each seen through the process's own mount namespace;
- that no such process holds an off-machine connection.

It exits 1 on any finding, and the nightly timer runs it after `profile --check`
(`~/.cache/harness42/reports/sovereign-<date>.md`). The network checks are one snapshot, and a
listener owned by root is shown as `info`, not judged: the Caveat in `tools/sovereign.sh`.

## White-hat scanning: `devil scan`

`devil scan <url>` runs ZAP's **baseline** (spider + passive rules, no attack payloads) in a
container pinned by digest, against an exact `scheme://host:port` listed in the overlay's
`scan.active` or `scan.passive`. It refuses:

- an unlisted host;
- a portless URL that does not match a listed port;
- the kit's own service ports (5678, 37777, 6767, 8282, 9050, 9052);
- wildcard or portless allowlist entries;
- `user@host` tricks and non-http schemes;
- `--full`.

[`tests/test_scan.sh`](../tests/test_scan.sh) proves each refusal.

## Risk verdicts (the devil, 2026-10-30)

| Item | Verdict | Conditions that bind the build |
|---|---|---|
| n8n on the host with a shell | PROCEED-WITH-CONDITIONS | see list below |
| n8n's MCP Server Trigger as a user MCP | **BLOCK** | `hooks/scripts/risk.py` guards only `Bash`, so `mcp__n8n__*` would be an unguarded host shell. Lift when it has bearer auth, fixed tool arguments and `permissions.ask` on `mcp__n8n__*` |
| rtk, claude-mem hooks | PROCEED-WITH-CONDITIONS | see list below |
| security-guidance, fly hooks | PROCEED | — |
| ZAP active scan + MCP add-on | **BLOCK** | the add-on's context tool lets the agent put any URL in scope, and `*.tail10f2ea.ts.net` holds a live database. Baseline ships now (Z1: exact allowlist, Z4: memory cap, Z5: no proxy); active scans and the add-on wait for a re-submission |

Conditions for n8n on the host:

- pinned 2.45.7 with a committed lockfile;
- webhook, form and file triggers stay excluded;
- `~/.ssh`, `~/.config/gh` and `~/.gnupg` are unreadable to n8n (masked by bubblewrap: `InaccessiblePaths=` is skipped silently on Ubuntu, see the unit);
- `MemoryMax=768M`;
- no `claude -p` call that bypasses permissions;
- telemetry off;
- bound to 127.0.0.1;
- the nightly job is a systemd timer, not n8n.

Conditions for the rtk and claude-mem hooks:

- the kit's ask/deny beats rtk's allow (G1, G2);
- no rtk PostToolUse hook, telemetry off, failures still exit non-zero;
- claude-mem passes a secret canary;
- claude-mem's 32 KiB Read gate is turned off or documented;
- pinned uv/bun are installed first;
- claude-mem's worker listens on loopback only.

## Supermemory: killed (trial, 2026-10-31)

The self-hosted server (`server-v0.0.9`, standalone linux-x64 binary, sha256 verified) refuses to
start without a model-provider key: "No model provider API key configured. Set one of
OPENAI_API_KEY, ANTHROPIC_API_KEY, GEMINI_API_KEY, GROQ_API_KEY". Each of those is either paid (the
Anthropic API is billed apart from a Claude plan) or a cloud service that would receive the
memories. That breaks both free and local, and the free "lite" licence also caps the store at 10k
documents. The supermemory role is covered by claude-mem (automatic, local, redacted) plus
auto-memory (curated). To revisit: a free local LLM provider, or a machine with a GPU for one.

## Conditions proven (2026-10-31)

| Condition | Evidence |
|---|---|
| G1: force-push refused | the devil hook returns `deny`: "Refused: force-push to a protected branch" |
| G2: the kit's ask beats rtk | the devil hook returns `ask` for `git push --dry-run`. rtk only rewrites the command (`permissionDecision: null`) |
| R1: no rtk PostToolUse | `jq .hooks ~/.claude/settings.json` shows one PreToolUse `rtk hook claude` |
| R2: rtk telemetry off | `rtk telemetry status` reports `consent: no` |
| R3: failures still fail | `rtk git status` outside a repo exits 128; `rtk ls /missing` exits 2 |
| C1: secret canary | **failed first**: claude-mem stores raw tool input, and its redaction is opt-in. With `CLAUDE_MEM_REDACT_ENABLED` and `CLAUDE_MEM_REDACT_GENERIC_ENABLED` on, a fresh `ghp_` token and an `API_TOKEN=` value land as `<redacted type='github_pat'/>` and `<redacted type='generic_token'/>`, with 0 raw hits in the db, WAL or logs |
| C2: Read gate | `CLAUDE_MEM_FILE_READ_GATE_ENABLED=false` |
| C3: pinned runtimes | uv 0.13.6 and bun 1.4.4 are installed by the tools stage before claude-mem |
| C4: loopback only | `ss -ltn` shows `127.0.0.1:37700` |

claude-mem's telemetry defaults to ON (PostHog). The worker ran for about a minute with that default
before the three off-switches were added, so a lifecycle event may have left the machine then.

## n8n supply chain (osv-scanner, 2026-10-31)

`osv-scanner v2.2.3 scan source --lockfile profiles/n8n/package-lock.json`. n8n 2.45.7 is the
latest stable (`npm view n8n dist-tags`), so a newer n8n is not the fix.

| Lockfile | Vulnerable packages | Critical (≥ 9) | High (7–9) |
|---|---|---|---|
| n8n as published | 48 | 4 | 24 |
| with `overrides` in `profiles/n8n/package.json` | 39 | 1 | 17 |

The overrides only move a package to a fixed version in the **same major**: form-data, both
fast-xml-parser lines, axios, `@modelcontextprotocol/sdk`/`server`/`node`, ws, undici, linkify-it
5, the Jaeger propagator. Every fix that would need a new major stays out, because forcing it
could break n8n in ways no test here would catch. That covers tar 6, uuid, zod 3, toml 3,
markdown-it 13, nodemailer 7, msal-node, adm-zip, langsmith and the OpenTelemetry SDK.
The remaining critical, `tar@6.2.1`, comes only through node-gyp and cacache, at build
time. These residuals are accepted because n8n listens on 127.0.0.1 only and has no inbound
triggers. Re-run the scan when n8n ships a new stable.

Live conditions, measured after `devil profile --apply --pack orchestrator`:

| Condition | Evidence |
|---|---|
| loopback only | `ss -ltn`: `127.0.0.1:5678` (UI) and `127.0.0.1:5679` (task-runner broker), nothing else. The LAN IP does not answer, and 5 minutes after start n8n holds 0 non-loopback connections |
| no inbound triggers | `POST /webhook/test` → 404 |
| secrets unreadable | **failed first**: `InaccessiblePaths=` was skipped silently (n8n shared the host's mount namespace and listed `~/.ssh`). Under bwrap, n8n's namespace differs from the host's and `~/.ssh`, `~/.config/gh`, `~/.gnupg`, `~/.config/42ctl` hold 0 entries; the host's copies are intact |
| memory cap | `systemctl --user show -p MemoryMax`: 805306368 (768M); about 560 MiB used at idle |
| nightly check | `harness42-profile-check.timer` enabled, next run 03:30 |
| no MCP trigger | not registered; `tests/test_n8n.sh` fails if a workflow carries one |

The owner account is created by hand in the browser at `http://127.0.0.1:5678` on first visit.
Nobody else can reach that page.

Install scripts are gated by `allowScripts` (npm 11). Only sqlite3, isolated-vm and
msgpackr-extract may build, each pinned to its version. The other 13 are denied, among them
`@scarf/scarf` (install analytics) and the two `@sentry` profilers. `tests/test_n8n.sh` holds
the static half of the conditions above.

## Caveats

- **Pins are a snapshot.** "Widely used in October 2026" was researched on 2026-10-30 and
  goes stale. Bumping is a deliberate edit to `profiles/user.json` plus a re-apply, never an
  automatic update.
- **Floating official plugins.** The official marketplace updates itself, so two machines applied a
  week apart can differ there. `user.lock.json` says how.
- **Install everything costs context.** The budget stage prints the always-on total. Measure it
  before raising the ceiling.
- **`playwright install` prunes.** Each run deletes the browser builds no registered Playwright
  still references, so one project's install can remove another's. The profile pins the
  playwright MCP's own version (build 1247); re-run a project's `npx playwright install` after it.
- **Tor egress.** Downloads and OAuth logins may need a retry. A failed download is `cannot`
  (exit 2), never a silent pass.
