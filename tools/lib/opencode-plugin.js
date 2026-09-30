// The OpenCode 2.x hook bridge. Copied verbatim into dist/opencode/plugins/devil.js
// by `devil export opencode`; edit it here, never there.
//
// The kit's enforcement lives in hooks/scripts/hooks.py, which speaks Claude Code's
// hook protocol on stdin/stdout. This file is the adapter: it translates the four
// V2 hook domains into that one protocol and translates the answer back.
//
// Measured on OpenCode 2.0.18 (2026-09-30, doc/HARNESSES.md "OpenCode, measured
// for X1"):
//   - setup() must register its hooks synchronously. An `async setup` that awaits
//     its registrations, or one that lets a transform throw, leaves the hooks
//     registered but never fired.
//   - permission.evaluate fires for every action, including effect "allow", with
//     event.action = "shell" and event.resources = [the raw command text].
//   - tool.execute.before/after fire with event.tool in {shell, read, write, ...};
//     the write input is {path, content}, the shell input is {command}.
//   - shell.create.before can set event.env, which is how bin/ reaches the PATH.
//   - session.context fires on every model call and event.system is a pushable
//     array of {type, text}. There is no session-start hook and no field on
//     tool.execute.after that injects context, so both are delivered here.
//
// Caveat: this file resolves the kit from its own location
// (dist/opencode/plugins/devil.js -> ../../../). That path is only right for the
// generated copy; running this source file in place finds the wrong kit and the
// bridge silently denies nothing.
import { spawnSync } from "node:child_process"
import { appendFileSync, existsSync, readFileSync, readdirSync } from "node:fs"
import { dirname, join, resolve } from "node:path"
import { fileURLToPath } from "node:url"

const KIT = resolve(dirname(fileURLToPath(import.meta.url)), "../../..")
const HOOKS = join(KIT, "hooks", "scripts", "hooks.py")
const RULES = join(KIT, "rules")
const BIN = join(KIT, "bin")
const DEBUG = process.env.DEVIL_BRIDGE_DEBUG
const dbg = (m) => {
  if (DEBUG) {
    try {
      appendFileSync(DEBUG, m + "\n")
    } catch {}
  }
}

// The kit answers "ask" on the irreversible. OpenCode has a real ask channel, so
// the decision is passed through rather than flattened into a deny.
const DECISIONS = ["deny", "ask"]

// risk.py and gates.py only have rules for these; every other action would be a
// wasted process spawn per tool call.
const ACTION_TOOL = { shell: "Bash", edit: "Write" }
const EDIT_TOOLS = ["write", "edit", "patch", "multiedit"]

// A compound shell command is split before the permission hook sees it, and only
// the FIRST segment is offered: measured 2026-09-30, `command -v devil; echo
// git push --force origin main` reached the permission hook as
// `command -v devil` and the rest ran. So a segmented command is checked a
// second time in the tool hook, which sees the whole string. A single-segment
// command was already checked in full and is not re-spawned.
// Caveat: the separator test is a regex over the command text, so a separator
// built at runtime (`eval`, a variable holding `;`) is invisible here, exactly
// as it is invisible to risk.py's own matcher.
const SEGMENTED = /[;&|`\n]|\$\(/

// Queued text waiting for the next model call: a post-edit gate verdict, or the
// session briefing. session.context is the only channel V2 offers for both.
const pending = []
let host = ""
let rulesPushed = false
const briefed = new Set()

// Ask hooks.py. Anything unexpected here is a no-op, which is the same contract
// hooks.py itself keeps: a broken hook must never stop the user working.
function ask(payload) {
  if (!existsSync(HOOKS)) return null
  try {
    const done = spawnSync("python3", [HOOKS], {
      input: JSON.stringify(payload),
      encoding: "utf8",
      timeout: 4000,
      env: { ...process.env, CLAUDE_PROJECT_DIR: host, CLAUDE_PLUGIN_ROOT: KIT },
    })
    if (done.status !== 0 || !done.stdout) return null
    return JSON.parse(done.stdout).hookSpecificOutput || null
  } catch {
    return null
  }
}

function additionalContext(payload) {
  const answer = askImpl(payload)
  return answer && typeof answer.additionalContext === "string" ? answer.additionalContext : null
}

// The 12 always-on rules, as one system entry. OpenCode V2 reads AGENTS.md and
// nothing else; this is the file-free route to the same always-on text Claude Code
// gets from rules/. Read once, at setup, so no model call pays for a disk walk.
function rulesText() {
  try {
    return readdirSync(RULES)
      .filter((f) => f.endsWith(".md"))
      .sort()
      .map((f) => "<!-- rules/" + f + " -->\n" + readFileSync(join(RULES, f), "utf8"))
      .join("\n\n")
  } catch {
    return ""
  }
}

function bashPayload(command) {
  return { hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: { command }, cwd: host }
}

function writePayload(filePath) {
  return { hook_event_name: "PreToolUse", tool_name: "Write", tool_input: { file_path: filePath }, cwd: host }
}

function enforce(event) {
  const tool = ACTION_TOOL[event.action]
  const resource = String((event.resources || [])[0] || "")
  const shown = JSON.stringify(resource.slice(0, 120))
  dbg(`enforce action=${event.action} mapped=${tool || "none"} resource=${shown}`)
  if (!tool) return
  if (!resource) return
  const answer = askImpl(tool === "Bash" ? bashPayload(resource) : writePayload(resource))
  if (!answer || !DECISIONS.includes(answer.permissionDecision)) return
  event.effect = answer.permissionDecision
  event.message = answer.permissionDecisionReason || "devil: refused with no reason given"
}

// The backstop for a segmented command the permission hook never saw whole.
// Throwing is the only channel a tool hook has, so an `ask` decision arrives as a
// refusal with the kit's reason attached: stricter than a prompt, never looser.
function guardSegmented(event) {
  if (event.tool !== "shell") return
  const command = String((event.input || {}).command || "")
  if (!SEGMENTED.test(command)) return
  dbg("guardSegmented whole=" + JSON.stringify(command.slice(0, 120)))
  const answer = askImpl(bashPayload(command))
  if (answer && DECISIONS.includes(answer.permissionDecision)) {
    throw new Error(answer.permissionDecisionReason || "devil: refused with no reason given")
  }
}

function gateEditedFile(event) {
  if (!EDIT_TOOLS.includes(event.tool)) return
  const input = event.input || {}
  const filePath = input.path || input.filePath
  if (!filePath) return
  const payload = {
    hook_event_name: "PostToolUse",
    tool_name: "Edit",
    tool_input: { file_path: filePath },
    cwd: host,
  }
  const text = additionalContext(payload)
  if (text) pending.push(text)
}

function brief(sessionID) {
  if (!sessionID || briefed.has(sessionID)) return
  briefed.add(sessionID)
  const payload = { hook_event_name: "SessionStart", source: "startup", cwd: host }
  const text = additionalContext(payload)
  if (text) pending.push(text)
}

export default {
  id: "devil",
  setup(ctx) {
    host = ctx.location?.project?.directory || ctx.location?.directory || process.cwd()
    const rules = rulesText()
    dbg("setup host=" + host + " kit=" + KIT + " rulesBytes=" + rules.length)

    ctx.permission.hook("evaluate", enforce)
    ctx.tool.hook("execute.before", guardSegmented)
    ctx.tool.hook("execute.after", gateEditedFile)
    ctx.shell.hook("create.before", (event) => {
      event.env.PATH = BIN + ":" + (event.env.PATH || "")
    })
    ctx.session.hook("context", (event) => {
      dbg("context fired, systemLen=" + event.system.length + " rulesBytes=" + rules.length)
      brief(event.sessionID)
      if (!rulesPushed && rules) {
        rulesPushed = true
        event.system.push({ type: "text", text: rules })
      }
      while (pending.length > 0) event.system.push({ type: "text", text: pending.shift() })
      dbg("context done, systemLen=" + event.system.length)
    })
  },
}

// The test seam. The payload mapping and the decision handling are the two parts
// of this file worth asserting without a live session, and both are pure once the
// one function that talks to python is replaceable. OpenCode reads only the default
// export above, so this changes nothing at runtime.
let askImpl = ask
export const bridge = {
  setAsk: (fn) => {
    askImpl = fn
  },
  bashPayload,
  writePayload,
  enforce,
  guardSegmented,
  SEGMENTED,
}
