# `hooks/sounds/` — empty on purpose

Audio notification is supported and **no audio files ship with this repo**.

Two reasons. Committing several megabytes of generated audio into a config that is meant
to be copied into every project is a poor trade — most people never enable it, everyone
pays to clone it. And sound is the most personal setting there is; a default someone
else picked is a default you will turn off.

## Turning it on

1. Drop files into a directory named after the event, lowercased:

   ```
   hooks/sounds/
   ├── pretooluse/      any .wav or .mp3
   ├── posttooluse/
   ├── stop/
   ├── sessionstart/
   ├── notification/
   └── permissionrequest/
   ```

   The first file found in the directory is played. `.wav` is preferred over `.mp3`
   because it starts without a decode delay.

2. Enable it in `config/hooks-config.local.json` (gitignored, so it stays yours):

   ```json
   { "sounds": true }
   ```

3. A player has to be on `PATH`. The handler tries `paplay`, `aplay`, `afplay`
   (macOS), then `ffplay`. If none is present, sound is skipped silently — it will
   never break a session.

## Which events are worth a sound

Most are not. Three actually earn one, because each marks a moment you are not looking
at the terminal:

- **`permissionrequest`** — you are being asked for something and the run is stopped
  until you answer.
- **`stop`** — the turn finished.
- **`notification`** — the harness wants your attention.

Wiring up all 25 produces noise you stop hearing within an hour, which is the same as
having none.

## Making them

Any short clip works. Keep them under ~400ms and distinct from each other — you are
identifying the event by ear, not enjoying it. Text-to-speech, a synth, or a trimmed
UI-sound pack are all fine.

`.gitignore` covers `hooks/sounds/*/`, so your files stay local unless you deliberately
force-add them.
