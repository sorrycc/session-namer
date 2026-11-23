# session-namer

Give every Claude Code session a real name, automatically.

Claude Code lists sessions by id and first message, which makes `/resume` a
guessing game. This plugin names each session with a single model call on the
conversation so far, so your session list reads like a task list:

```
Add Incline Dwelling Policy Alias
Design Bordereau Schedule UI
[AH-40] Fix Excluded Procedure Mapper Modifier Drop
```

The default format is a short task title: Title Case, starting with an
imperative verb, 3 to 6 words, in the language you write in. When the session
is about an issue-tracker ticket, its id is prefixed in square brackets. The
id is taken from the conversation or from the git branch name, so a branch
called `ah-40-excluded-procedures` is enough. Any other convention can be
configured, see below.

## Install

```
/plugin marketplace add coxjc/cc-session-namer
/plugin install session-namer@session-namer
```

Update later with `/plugin update`.

Requires `jq` and the `claude` CLI on your `PATH`.

## Configuration

Everything is optional. Out of the box you get the format shown above.

| Variable | Default | Purpose |
| --- | --- | --- |
| `SESSION_NAMER_FORMAT` | built-in | Naming convention, written as prose for the model |
| `SESSION_NAMER_DISABLE` | unset | Set to any value to turn the plugin off |
| `SESSION_NAMER_CLAUDE_BIN` | `claude` | CLI used to write the name, looked up on `PATH` |
| `SESSION_NAMER_MAX_RENAMES` | `3` | How many times the plugin may name one session |
| `SESSION_NAMER_RECHECK_EVERY` | `5` | Reconsider the name every this many turns |
| `SESSION_NAMER_DEBUG` | unset | Set to any value to log every run to `$TMPDIR/session-namer.log` |

The convention is resolved in this order: `SESSION_NAMER_FORMAT`, then a
per-project file, then the built-in default.

Set variables under `env` in your `settings.json`:

```json
{
  "env": {
    "SESSION_NAMER_FORMAT": "Format: <area>: <what changed>, in English, max 6 words, lowercase."
  }
}
```

For a per-project convention, write it to `.claude/session-name.md`:

```
Format: [TICKET] short imperative title in English, max 8 words.
Use [NOJIRA] when no ticket is mentioned.
```

Those two examples produce, respectively:

```
api: add rate limiting to public endpoints
[NOJIRA] Migrate billing cron to new scheduler
```

## How it works

The plugin registers two async hooks, so the model call never blocks your turn:

- **`UserPromptSubmit`** names the session as the conversation takes shape.
- **`SessionStart`** covers resumed sessions, using the existing transcript.

A session's title is the last `{"type":"custom-title"}` line in its transcript.
Appending one renames the session, which is the same mechanism `/rename` uses.
A name you set with `/rename` is never overwritten.

The only network call is the model request. It runs `claude -p` on Haiku in a
bare configuration: a short system prompt of its own, no tools, no MCP
servers, and no saved session, so it never shows up in `/resume`. It carries
the whole conversation, meaning every user and assistant message as text,
without tool calls, tool output or thinking, plus the current title and your
convention. A conversation longer than 100,000 characters is sent as its
first 20,000 and its last 80,000.

### Naming behavior

- A prompt with no task, such as a greeting or a test message, is skipped. The
  session stays unnamed until real work arrives. An unnamed session is tried
  on every prompt for its first `SESSION_NAMER_RECHECK_EVERY` turns, and every
  that many turns after.
- The name reflects the conversation so far, not the single prompt that
  triggered the hook.
- The plugin's own names are provisional. Every `SESSION_NAMER_RECHECK_EVERY`
  turns the name is reconsidered, and if the work has clearly moved on it is
  upgraded, up to `SESSION_NAMER_MAX_RENAMES` times. A name that still fits is
  left alone.
- With the built-in format, output longer than 10 words is discarded as the
  model explaining itself. A custom convention is only checked for being
  non-empty.

```
"hello"                                              → (unnamed)
"thanks!"                                            → (unnamed)
"add exponential backoff to payment gateway retries" → Add Payment Gateway Retry Backoff
"cap the backoff at 30 seconds"                      → Add Payment Gateway Retry Backoff   (unchanged)
"forget payments, move CI to GitHub Actions"         → Move CI to GitHub Actions
"pick up ENG-1234, the export drops september rows"  → [ENG-1234] Fix Export Dropping September Rows
```

A conversation in another language gets its title in that language.

### Troubleshooting

If a session stays unnamed, set `SESSION_NAMER_DEBUG=1` and read
`$TMPDIR/session-namer.log`. Each run writes one line saying what it decided,
and any error from the CLI lands in the same file.

## Background

Why this exists: https://x.com/chenchengpro/status/2095410400720482506

## License

MIT
