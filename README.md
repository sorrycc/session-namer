# session-namer

Give every Claude Code session a real name, automatically.

Claude Code lists sessions by id and first message, which makes `/resume` a
guessing game. This plugin names each session with a single model call on the
conversation so far, so your session list reads like a changelog:

```
0904 fix: login token lost on refresh
0904 feat: 添加会话自动命名钩子
0903 refactor: batch text rendering
```

The default format is `MMDD type: summary`. The date is the day the session
started. The type is one of feat, design, fix, refactor, release, explore,
docs, research, chore. The summary is written in the language you write in:
at most 6 words in English, or 10 characters in Chinese or Japanese. Any other
convention can be configured, see below.

## Install

```
/plugin marketplace add sorrycc/session-namer
/plugin install session-namer@session-namer
```

Update later with `/plugin update`.

Requires `jq` and the `claude` CLI on your `PATH`. Under QoderCLI the
`qodercli` CLI is used instead, automatically; see below.

## Configuration

Everything is optional. Out of the box you get the format shown above.

| Variable | Default | Purpose |
| --- | --- | --- |
| `SESSION_NAMER_FORMAT` | built-in | Naming convention, written as prose for the model |
| `SESSION_NAMER_MODEL` | `sonnet`, or `Efficient` under QoderCLI | Model that writes the name |
| `SESSION_NAMER_DISABLE` | unset | Set to any value to turn the plugin off |
| `SESSION_NAMER_CLAUDE_BIN` | `claude`, or `qodercli` under QoderCLI | CLI used to write the name, looked up on `PATH` |
| `SESSION_NAMER_MAX_RENAMES` | `3` | How many times the plugin may name one session |
| `SESSION_NAMER_MAX_TURNS` | `20` | Stop trying to name a still-unnamed session after this many turns |
| `SESSION_NAMER_RECHECK_EVERY` | `5` | Once named, reconsider the name every this many turns |
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

### QoderCLI

Nothing to configure. The plugin recognises QoderCLI from the environment it
gives its hooks, calls `qodercli` (or `qoderclicn`, the CN edition) instead of
`claude`, and asks the `Efficient` tier for the name. If that tier is not in
your account's catalog, the call is retried with your default model.
`qodercli --list-models` shows the tiers; set `SESSION_NAMER_MODEL` to use
another one.

The per-project file is read from `.qoder/session-name.md`, with `.claude/`
as a fallback. QoderCLI has no `env` block in its `settings.json`, so to set
any of the variables above put them in `.qoder/.env` in the project or in
`~/.qoder/.env`:

```
SESSION_NAMER_MODEL=Lite
```

## How it works

The plugin registers two async hooks, so the model call never blocks your turn:

- **`UserPromptSubmit`** names the session as the conversation takes shape.
- **`SessionStart`** covers resumed sessions, using the existing transcript.

A session's title is the last `{"type":"custom-title"}` line in its transcript.
Appending one renames the session, which is the same mechanism `/rename` uses.
A name you set with `/rename` is never overwritten.

The only network call is the model request. It runs `claude -p`, or
`qodercli -p` under QoderCLI, in a bare configuration: a short system prompt
of its own, no tools, no MCP servers, and no saved session, so it costs a few
hundred tokens and never shows up in `/resume`. It carries up to the first
three and last three user turns, capped at 2000 characters, plus the current
title and your convention.

### Naming behavior

- A prompt with no task, such as a greeting or a test message, is skipped. The
  session stays unnamed until real work arrives.
- The name reflects the conversation so far, not the single prompt that
  triggered the hook.
- The plugin's own names are provisional. Every `SESSION_NAMER_RECHECK_EVERY`
  turns the name is reconsidered, and if the work has clearly moved on it is
  upgraded, up to `SESSION_NAMER_MAX_RENAMES` times. A name that still fits is
  left alone.
- With the built-in format, output that does not match the expected shape is
  discarded. A custom convention is only checked for being non-empty.

```
"hello"                                              → (unnamed)
"thanks!"                                            → (unnamed)
"add exponential backoff to payment gateway retries" → 0904 feat: payment gateway retry backoff
"cap the backoff at 30 seconds"                      → 0904 feat: payment gateway retry backoff   (unchanged)
"forget payments, move CI to GitHub Actions"         → 0904 chore: move ci to github actions
```

A conversation in another language gets its summary in that language, with
the type kept in English:

```
"重构支付网关的重试逻辑，加上指数退避"                    → 0904 refactor: 支付网关重试指数退避
```

### Troubleshooting

If a session stays unnamed, set `SESSION_NAMER_DEBUG=1` and read
`$TMPDIR/session-namer.log`. Each run writes one line saying what it decided,
and any error from the CLI lands in the same file.

## Background

Why this exists: https://x.com/chenchengpro/status/2095410400720482506

## License

MIT
