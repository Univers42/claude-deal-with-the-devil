#!/usr/bin/env bash
# test_export_codex.sh — the Codex export must be reproducible, complete and honest.
#
# Same shape as tests/test_export.sh, and the same priority: a generator is only
# worth having if drift is loud, so the negative controls are the point. A test
# that only proves the happy path would pass just as well with a broken generator.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
SKIP=0

ok() {
  echo "ok   - $1"
  PASS=$((PASS + 1))
}
no() {
  echo "FAIL - $1"
  FAIL=$((FAIL + 1))
}
skip() {
  echo "skip - $1"
  SKIP=$((SKIP + 1))
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The portable manifest schema sets additionalProperties false, so a Claude Code
# field leaking into it is the failure mode the source has to be guarded against:
# Codex would reject the package outright. This is the allowed key set, verbatim
# from https://agent-plugins.org/schemas/1.0.0/plugin.schema.json (fetched
# 2026-09-30), plus the one OpenAI extension namespace Codex documents.
ALLOWED_MANIFEST_KEYS='["$schema","name","version","description","author","homepage","repository","license","keywords","extensions"]'
# The twelve events Codex 0.159.2 fires. A seventeenth would be dead weight.
CODEX_EVENTS='["Interrupt","PermissionRequest","PostCompact","PostToolUse","PreCompact","PreToolUse","SessionEnd","SessionStart","Stop","SubagentStart","SubagentStop","UserPromptSubmit"]'

# --- 1. the committed tree is what the sources generate ------------------------
if out="$(cd "$ROOT" && bash tools/export.sh --check codex 2>&1)"; then
  ok "committed dist/codex matches its sources"
else
  no "committed dist/codex is stale: $out"
fi

# A hand edit to a generated file is drift. Proved by making one.
DRIFT="$ROOT/dist/codex/AGENTS.md"
cp "$DRIFT" "$TMP/agents.keep"
printf '\nhand edit\n' >>"$DRIFT"
if (cd "$ROOT" && bash tools/export.sh --check codex >/dev/null 2>&1); then
  no "a hand-edited generated file must fail --check"
else
  ok "a hand-edited generated file fails --check"
fi
cp "$TMP/agents.keep" "$DRIFT"
if (cd "$ROOT" && bash tools/export.sh --check codex >/dev/null 2>&1); then
  ok "restoring the file clears the drift"
else
  no "restore must put the tree back in sync"
fi

# An unknown harness is exit 2, never a silent pass.
(cd "$ROOT" && bash tools/export.sh --check nosuch >/dev/null 2>&1)
[ $? -eq 2 ] && ok "unknown harness exits 2" || no "unknown harness must exit 2"

# The opencode export must be untouched by this slice. Compared by fingerprint
# before and after running the codex export, not by `--check opencode`: that check
# reports drift in the committed opencode tree that predates this slice (see
# next:), and a test that fails on someone else's known state is a test nobody
# reads. What this slice must prove is that it writes nothing there.
before="$(find "$ROOT/dist/opencode" -type f -exec md5sum {} + | sort)"
(cd "$ROOT" && bash tools/export.sh codex >/dev/null 2>&1)
after="$(find "$ROOT/dist/opencode" -type f -exec md5sum {} + | sort)"
if [ "$before" = "$after" ]; then
  ok "running the codex export writes nothing into dist/opencode"
else
  no "the codex export modified dist/opencode"
fi

# --- 2. the generated manifests are what Codex will accept -------------------
# Both are JSON, both are read by Codex at install time, and a parse failure is a
# package that does not install. python3 parses them the way Codex's loader does.
if command -v python3 >/dev/null 2>&1; then
  badjson="$(python3 -c 'import json,sys; json.load(open(sys.argv[1]))' \
    "$ROOT/dist/codex/plugin.json" 2>&1 &&
    python3 -c 'import json,sys; json.load(open(sys.argv[1]))' \
      "$ROOT/dist/codex/hooks/hooks.json" 2>&1)"
  [ -z "$badjson" ] && ok "plugin.json and hooks/hooks.json are valid JSON" ||
    no "a generated manifest is not valid JSON: $badjson"

  # The version must be copied from .claude-plugin/plugin.json, never written by
  # the generator: two version sources is how a release ships a manifest the
  # plugin does not match.
  # A manifest version read twice, once from each file. Python's sys is imported
  # in every -c here: a missing import would make the check print an empty string
  # and the comparison would silently pass on two empty strings.
  readver() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$1"; }
  srcver="$(readver "$ROOT/.claude-plugin/plugin.json")"
  gotver="$(readver "$ROOT/dist/codex/plugin.json")"
  if [ -n "$srcver" ] && [ "$srcver" = "$gotver" ]; then
    ok "the manifest carries the plugin.json version ($gotver)"
  else
    no "manifest version '$gotver' does not match plugin.json '$srcver'"
  fi

  # A negative control on that same check: the assertion must be able to fail, or
  # a manifest with the wrong version would pass as loudly as a correct one.
  printf '{"name":"devil","version":"0.0.0-wrong"}' >"$TMP/wrong.json"
  if [ "$(readver "$TMP/wrong.json")" != "$srcver" ]; then
    ok "a manifest with the wrong version is detected (negative control)"
  else
    no "the version check cannot fail, so it proves nothing"
  fi

  # Only schema-allowed keys, and the OpenAI hooks pointer Codex needs to find the
  # generated hook file instead of relying on its default path.
  # A parse error here must fail the check, not print nothing and pass it: the
  # unexpected-key list is empty both when the manifest is clean and when the
  # checker is broken.
  extra="$(
    python3 - "$ROOT/dist/codex/plugin.json" "$ALLOWED_MANIFEST_KEYS" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    allowed = set(json.loads(sys.argv[2]))
except Exception as exc:
    sys.stderr.write(str(exc) + "\n")
    sys.exit(1)
print(" ".join(k for k in d if k not in allowed))
PY
  )" || extra="checker failed"
  [ -z "$extra" ] && ok "the manifest carries no key the portable schema forbids" ||
    no "the manifest has keys the schema rejects: $extra"
  if grep -q '"hooks": "./hooks/hooks.json"' "$ROOT/dist/codex/plugin.json"; then
    ok "the manifest points extensions.com.openai at the generated hooks file"
  else
    no "extensions.com.openai.hooks does not name hooks/hooks.json"
  fi

  # That checker's negative control: a manifest carrying a Claude Code key must be
  # reported, or "no unexpected keys" would be the empty-set tautology it looks like.
  printf '{"name":"devil","displayName":"Deal with the Devil"}' >"$TMP/forbidden.json"
  gotextra="$(
    python3 - "$TMP/forbidden.json" "$ALLOWED_MANIFEST_KEYS" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
allowed = set(json.loads(sys.argv[2]))
print(" ".join(k for k in d if k not in allowed))
PY
  )"
  if [ -n "$gotextra" ]; then
    ok "a key outside the schema is reported (negative control)"
  else
    no "the unexpected-key checker reports nothing, so it proves nothing"
  fi

  # Every event in the generated file must be one Codex fires, and every event
  # the kit declares that Codex does fire must be present. The set is the
  # intersection rather than the full twelve: `Interrupt` is a Codex event the kit
  # does not declare, and generating a handler for an event with nothing to run it
  # on would be inventing behaviour.
  evfaults="$(
    python3 - "$ROOT/dist/codex/hooks/hooks.json" "$ROOT/hooks/hooks.json" "$CODEX_EVENTS" <<'PY'
import json, sys
got = set(json.load(open(sys.argv[1]))["hooks"])
src = set(json.load(open(sys.argv[2]))["hooks"])
codex = set(json.loads(sys.argv[3]))
bad = []
for e in sorted(got - codex):
    bad.append(e + " is not an event Codex fires")
for e in sorted((src & codex) - got):
    bad.append(e + " is an event Codex fires and the kit declares, but it is missing")
print("\n".join(bad))
PY
  )"
  [ -z "$evfaults" ] && ok "the hooks file carries exactly the Codex events, no more, none missing" ||
    no "hook event set is wrong:"$'\n'"$evfaults"

  # The other way round, as a negative control: the seventeen events Codex never
  # fires must not be in the file at all.
  dropped="$(
    python3 - "$ROOT/hooks/hooks.json" "$CODEX_EVENTS" <<'PY'
import json, sys
src = json.load(open(sys.argv[1]))["hooks"]
codex = set(json.loads(sys.argv[2]))
print(" ".join(sorted(set(src) - codex)))
PY
  )"
  if ! grep -qE "\"($(echo "$dropped" | tr ' ' '|'))\":" "$ROOT/dist/codex/hooks/hooks.json"; then
    ok "no event Codex never fires survived into the hooks file"
  else
    no "an event Codex never fires is still declared"
  fi

  # Codex runs one command string and has no `args` array, and caps SessionEnd and
  # Interrupt at 3 seconds whatever the source says. The kit declares 5 for both,
  # so this is the check that would catch a generator that copied instead of
  # translating.
  hookfaults="$(
    python3 - "$ROOT/dist/codex/hooks/hooks.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
bad = []
for event, groups in d["hooks"].items():
    cap = 3 if event in ("SessionEnd", "Interrupt") else None
    for group in groups:
        for h in group.get("hooks", []):
            if "args" in h:
                bad.append(event + " carries an args array")
            if not str(h.get("command", "")).startswith("python3 "):
                bad.append(event + " command is not a single string: " + str(h.get("command")))
            if "${CLAUDE_PLUGIN_ROOT}" in str(h.get("command", "")):
                bad.append(event + " still names the Claude variable")
            if cap is not None and int(h.get("timeout", cap)) > cap:
                bad.append(event + " timeout above the Codex cap")
print("\n".join(bad))
PY
  )"
  [ -z "$hookfaults" ] && ok "every hook command is one string on PLUGIN_ROOT, within the caps" ||
    no "hook dialect not translated:"$'\n'"$hookfaults"

  # The generated AGENTS.md is the twelve rules verbatim, so a rule edited in the
  # kit must show up in it. Compared by rule heading, not by byte count.
  missing_rules=""
  for f in "$ROOT"/rules/*.md; do
    heading="$(head -1 "$f")"
    grep -qF "$heading" "$ROOT/dist/codex/AGENTS.md" || missing_rules="$missing_rules $(basename "$f")"
  done
  [ -z "$missing_rules" ] && ok "every rule in the kit is in the generated AGENTS.md" ||
    no "AGENTS.md is missing rules:$missing_rules"
else
  skip "python3 unavailable: manifests not parsed, version and event set not asserted"
fi

# --- 3. a fixture kit: new assets appear, and the mapping is right -------------
# A fixture, not the real tree, so the test can add a rule and a hook event the kit
# does not have and assert the translation without touching generated output.
FIX="$TMP/kit"
mkdir -p "$FIX"/{agents,commands,skills/sample,tools/lib,rules,hooks/scripts,hooks,.claude-plugin}
cp "$ROOT/tools/export.sh" "$FIX/tools/"
cp "$ROOT/tools/lib/common.sh" "$ROOT/tools/lib/export-codex.sh" "$FIX/tools/lib/"
cp "$ROOT/tools/lib/codex-README.md" "$ROOT/tools/lib/codex-hooks.py" \
  "$ROOT/tools/lib/codex-manifest.py" "$FIX/tools/lib/"
chmod +x "$FIX/tools/export.sh"
printf '{"name":"devil","version":"9.9.9","description":"fixture"}' >"$FIX/.claude-plugin/plugin.json"
printf -- '---\nname: rules-x\n---\n\n# Fixture rule heading\n\nA rule.\n' >"$FIX/rules/rules-x.md"
printf -- '---\nname: sample\ndescription: a sample skill\n---\n\nBody\n' >"$FIX/skills/sample/SKILL.md"
cat >"$FIX/hooks/hooks.json" <<'JSON'
{
  "description": "fixture",
  "hooks": {
    "PreToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3",
            "args": ["${CLAUDE_PLUGIN_ROOT}/hooks/scripts/hooks.py"],
            "timeout": 5,
            "statusMessage": "Checking risk"
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3",
            "args": ["${CLAUDE_PLUGIN_ROOT}/hooks/scripts/hooks.py"],
            "timeout": 30,
            "async": true
          }
        ]
      }
    ],
    "ConfigChange": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3",
            "args": ["${CLAUDE_PLUGIN_ROOT}/hooks/scripts/hooks.py"]
          }
        ]
      }
    ]
  }
}
JSON

if (cd "$FIX" && bash tools/export.sh codex >/dev/null 2>&1); then
  ok "a fixture kit exports"
else
  no "the fixture kit must export"
fi

# A new rule reaches the generated AGENTS.md, and the version comes from the
# fixture's own manifest.
grep -qF 'Fixture rule heading' "$FIX/dist/codex/AGENTS.md" &&
  ok "a new rule appears in the generated AGENTS.md" ||
  no "rules/rules-x.md missing from the fixture AGENTS.md"
grep -q '"version": "9.9.9"' "$FIX/dist/codex/plugin.json" &&
  ok "the version is read from the fixture manifest, not hardcoded" ||
  no "the manifest version did not come from the source"

# Command + args fold into one string, and the event Codex never fires is dropped.
if grep -q '"command": "python3 ${PLUGIN_ROOT}/hooks/scripts/hooks.py"' \
  "$FIX/dist/codex/hooks/hooks.json"; then
  ok "command and args fold into one Codex command string"
else
  no "the fixture hook command was not folded into one string"
fi
grep -q 'ConfigChange' "$FIX/dist/codex/hooks/hooks.json" &&
  no "an event Codex never fires must be dropped" ||
  ok "an event Codex never fires is dropped"
grep -q '"timeout": 3' "$FIX/dist/codex/hooks/hooks.json" &&
  ok "SessionEnd timeout is clamped to the Codex cap" ||
  no "SessionEnd timeout must be clamped to 3 seconds"

# A negative control on the fold: a generator that left `args` in place would
# produce a file where Codex looks for one command string and finds an array.
if grep -q '"args"' "$FIX/dist/codex/hooks/hooks.json"; then
  no "the generated hooks file still carries an args array"
else
  ok "no args array survives in the generated hooks file"
fi

# A source manifest with a forbidden key must not carry it through.
FIXBAD="$TMP/kitbad"
cp -r "$FIX" "$FIXBAD"
printf '{"name":"devil","version":"9.9.9","displayName":"Deal with the Devil"}' \
  >"$FIXBAD/.claude-plugin/plugin.json"
(cd "$FIXBAD" && bash tools/export.sh codex >/dev/null 2>&1)
if grep -q 'displayName' "$FIXBAD/dist/codex/plugin.json"; then
  no "a Claude Code field must not reach the portable manifest"
else
  ok "a Claude Code field is dropped from the portable manifest"
fi

# --- 4. every generated skill, command or agent file has closed frontmatter ----
# dist/codex generates none of those, and that is the point: Codex reads a
# plugin's skills/ and rewrites commands/ itself. The check still runs, because a
# future slice that starts emitting them here must not emit a file whose
# frontmatter never closes. An unterminated block parses as no frontmatter at all:
# the name and description are silently lost and the skill never appears.
if command -v python3 >/dev/null 2>&1; then
  badfm="$(
    python3 - "$ROOT/dist/codex" <<'PY'
import glob, sys
root = sys.argv[1]
bad = []
for f in sorted(glob.glob(root + "/**/*.md", recursive=True)):
    if "/rules/" in f:
        continue
    text = open(f).read()
    if not text.startswith("---\n"):
        continue
    if "\n---\n" not in text[4:]:
        bad.append(f + " (frontmatter never closes)")
print("\n".join(bad))
PY
  )"
  [ -z "$badfm" ] && ok "every generated frontmatter block closes" ||
    no "frontmatter does not close:"$'\n'"$badfm"

  # The negative control for that check, on a file of the kind dist/codex would
  # emit if it ever generated a skill.
  mkdir -p "$TMP/fm/skills/unterminated"
  printf -- '---\nname: unterminated\ndescription: no closing fence\n\nBody.\n' \
    >"$TMP/fm/skills/unterminated/SKILL.md"
  got="$(
    python3 - "$TMP/fm" <<'PY'
import glob, sys
root = sys.argv[1]
bad = []
for f in sorted(glob.glob(root + "/**/*.md", recursive=True)):
    text = open(f).read()
    if not text.startswith("---\n"):
        continue
    if "\n---\n" not in text[4:]:
        bad.append(f)
print(len(bad))
PY
  )"
  [ "$got" -ge 1 ] && ok "an unterminated frontmatter file is detected (negative control)" ||
    no "the frontmatter check cannot fail, so it proves nothing"
else
  skip "python3 unavailable: generated frontmatter not parsed"
fi

# --- 5. the Codex CLI itself, in a container ----------------------------------
# codex is not on this host, so the manifest is exercised where the CLI can be
# installed. Only commands that need no account run: install from a local
# marketplace, list what loaded, and read the model-visible prompt. A hook firing
# needs a session and a model call, so that is recorded as not run, never as a
# pass. Without docker the whole block is a counted skip.
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  # The probe runs inside the container, so it is written into the mounted tree
  # rather than into $TMP: $TMP is on the host and is not visible from there.
  PROBE="$ROOT/target/test-probe-codex.sh"
  mkdir -p "$(dirname "$PROBE")"
  cat >"$PROBE" <<'PROBE_EOF'
set -u
npm i -g @openai/codex >/dev/null 2>&1 || { echo "PROBE npm install failed"; exit 1; }
mkdir -p /tmp/h /tmp/probe /tmp/mkt/.agents/plugins /tmp/mkt/plugins/devil
cd /tmp/probe
cp -r /w/dist/codex/. /tmp/mkt/plugins/devil/
ln -sfn /w/hooks/scripts /tmp/mkt/plugins/devil/hooks/scripts
printf '{"name":"x4mkt","interface":{"displayName":"X4"},"plugins":[{"name":"devil","source":{"source":"local","path":"./plugins/devil"},"policy":{"installation":"AVAILABLE","authentication":"ON_INSTALL"},"category":"Productivity"}]}\n' \
  >/tmp/mkt/.agents/plugins/marketplace.json
codex plugin marketplace add /tmp/mkt --json 2>&1 | grep -E 'marketplaceName|error'
codex plugin add devil@x4mkt --json 2>&1 | grep -E '"version"|installedPath|error'
codex plugin list 2>&1 | grep -E 'devil@x4mkt|not installed'
printf '{"name":"probeskill","description":"ZZPROBESKILL probe","version":"1.0.0"}\n' \
  >/tmp/mkt/.agents/plugins/marketplace.json
mkdir -p /tmp/probe/.agents/skills/probeskill
printf -- '---\nname: probeskill\ndescription: ZZPROBESKILL probe\n---\n\nBody.\n' \
  >/tmp/probe/.agents/skills/probeskill/SKILL.md
codex debug prompt-input hello 2>/dev/null >/tmp/pi.json
echo "project skills advertised: $(grep -c ZZPROBESKILL /tmp/pi.json || true)"
PROBE_EOF
  probeout="$(docker run --rm -v "$ROOT:/w" -w /w -e HOME=/tmp/h node:22-slim \
    bash /w/target/test-probe-codex.sh 2>&1)"
  rm -f "$PROBE"
  echo "$probeout" | sed 's/^/     /'
  wantver="$(python3 -c 'import json;print(json.load(open("'"$ROOT"'/.claude-plugin/plugin.json"))["version"])' 2>/dev/null || echo "")"
  if echo "$probeout" | grep -q "\"version\": \"$wantver\""; then
    ok "codex installs the generated plugin and reads the plugin.json version"
  else
    no "codex did not install the generated plugin at version $wantver"
  fi
  if echo "$probeout" | grep -q 'devil@x4mkt  installed, enabled'; then
    ok "codex plugin list reports the generated plugin installed and enabled"
  else
    no "codex plugin list does not report the plugin as installed"
  fi
  if echo "$probeout" | grep -q 'project skills advertised: 1'; then
    ok "a .agents/skills skill is advertised to the model"
  else
    no "a project skill under .agents/skills was not advertised"
  fi
  # A hook only fires inside a turn, and every turn needs a login this host does
  # not have. Recorded, not asserted.
  echo "note - hook execution and the deny path were not run: they need a session"
else
  skip "docker unavailable: the generated manifest was not exercised by the codex CLI"
fi

echo
echo "$PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ] || exit 1
