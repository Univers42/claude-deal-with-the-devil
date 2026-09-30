# The agent runs a wizard end to end is out of scope

- Decided: 2026-09-30 · by the maintainer
- Holds while: the wizard templates still drive a browser and write secrets

## The concept

Have the agent execute `templates/wizard.sh` from first stage to last, answering
its own prompts, so a provisioning run is verified rather than traced.

## Why not

A wizard is the one procedure whose correctness is a person typing into a terminal
that talks to a live dashboard. The agent cannot answer the prompts honestly (it
does not hold the credentials, and a guessed one is a written secret), and a run it
fakes proves nothing: the thing under test is the human interaction, which the
faking removes. So the only proof the agent can give is static, and that is what
ships.

- the static proof: `bash tests/test_templates.sh --trace <wizard>` proves every
  helper a stage calls exists and every secret name is a literal
- the secret handling that makes a real run unrepresentative: `templates/wizard.sh`,
  whose `--dry-run` deliberately runs with an empty `PATH`

## Prior requests

- 2026-09-30 (planning pass): let the agent run the wizard headless to prove the helper
  library, instead of tracing it statically.
- 2026-09-30 (planning pass, same day): keep the trace as the gate, and record the
  reversal here.

## Reopen when

A wizard stage is moved behind a flag that takes an input file instead of a human
answer, so the run has no prompt for the agent to fake. Then a headless fixture
run becomes possible, and it is added beside the trace, never instead of it.
