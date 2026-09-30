// Assert the two things about the OpenCode bridge that a live session cannot prove
// cheaply: the Claude-shaped payload it builds, and that a deny decision becomes
// the effect the host blocks on. Run by tests/test_export.sh; the harness, not
// this file, decides pass or fail.
import { bridge } from "../dist/opencode/plugins/devil.js"

let bad = 0
const is = (label, got, want) => {
  if (got === want) return
  console.log(`not ok - ${label}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`)
  bad += 1
}

// A V2 shell action carries the raw command in resources[0]; the bridge must hand
// hooks.py the Claude shape, or risk.py's Bash patterns never match.
const bash = bridge.bashPayload("git push --force origin main")
is("shell -> Bash", bash.tool_name, "Bash")
is("command preserved", bash.tool_input.command, "git push --force origin main")
is("event name", bash.hook_event_name, "PreToolUse")

const write = bridge.writePayload("/repo/.env")
is("edit -> Write", write.tool_name, "Write")
is("file_path preserved", write.tool_input.file_path, "/repo/.env")

// A deny decision must reach the host as a deny, with the kit's own reason.
bridge.setAsk(() => ({
  permissionDecision: "deny",
  permissionDecisionReason: "Refused: force-push to a protected branch.",
}))
const denied = { action: "shell", resources: ["git push --force origin main"], effect: "allow" }
bridge.enforce(denied)
is("deny effect", denied.effect, "deny")
is("deny reason", denied.message, "Refused: force-push to a protected branch.")

// The reverse: a hook that says nothing must not touch the decision. hooks.py
// prints nothing for ordinary work, and fail-open means the tool runs.
bridge.setAsk(() => null)
const quiet = { action: "shell", resources: ["ls -la"], effect: "allow" }
bridge.enforce(quiet)
is("silent hook leaves the effect alone", quiet.effect, "allow")
is("silent hook adds no message", quiet.message, undefined)

// ask is a decision, not a deny: the kit distinguishes "refuse" from "a human
// decides", and flattening the second into the first would block ordinary pushes.
bridge.setAsk(() => ({ permissionDecision: "ask", permissionDecisionReason: "publishes to a remote" }))
const asked = { action: "shell", resources: ["git push origin feature"], effect: "allow" }
bridge.enforce(asked)
is("ask effect", asked.effect, "ask")
is("ask reason", asked.message, "publishes to a remote")

// An action the kit has no rule for must not spawn anything or change anything.
let spawned = 0
bridge.setAsk(() => {
  spawned += 1
  return null
})
const read = { action: "read", resources: ["/repo/a.go"], effect: "allow" }
bridge.enforce(read)
is("read is left alone", read.effect, "allow")
is("read spawns nothing", spawned, 0)

// A compound command is the hole the permission hook leaves: OpenCode offers it
// only the first segment, so the bridge re-checks the whole string in the tool
// hook. Assert both halves: the separator test, and the refusal it produces.
for (const [cmd, want] of [
  ["ls -la", false],
  ["make build", false],
  ["a; b", true],
  ["a && b", true],
  ["a || b", true],
  ["a | b", true],
  ["a\nb", true],
  ["echo $(git push)", true],
  ["echo `git push`", true],
]) {
  is(`segmented(${JSON.stringify(cmd)})`, bridge.SEGMENTED.test(cmd), want)
}

bridge.setAsk(() => ({ permissionDecision: "deny", permissionDecisionReason: "Refused: whole string." }))
let threw = null
try {
  bridge.guardSegmented({ tool: "shell", input: { command: "ls; echo git push --force origin main" } })
} catch (e) {
  threw = e.message
}
is("a segmented command is refused whole", threw, "Refused: whole string.")

// A single-segment command was already fully checked by the permission hook, so
// the backstop must not pay for a second python process on ordinary work.
let respawned = 0
bridge.setAsk(() => {
  respawned += 1
  return null
})
threw = null
try {
  bridge.guardSegmented({ tool: "shell", input: { command: "ls -la" } })
} catch (e) {
  threw = e.message
}
is("an ordinary command is not re-checked", respawned, 0)
is("an ordinary command is not refused", threw, null)

if (bad > 0) {
  console.log(`${bad} assertion(s) failed`)
  process.exit(1)
}
console.log("bridge mapping ok")
