# session-namer

Give every Claude Code session a real name, automatically.

Claude Code sessions are listed by their id and first message, which makes `/resume`
a guessing game. This plugin names each session from its first prompt using a small
model, so your session list reads like a changelog:

```
0904｜修复｜登录页刷新token丢失
0904｜功能｜添加会话自动命名钩子
0903｜优化｜批次文字显示
```

## Install

```
/plugin marketplace add sorrycc/session-namer
/plugin install session-namer@session-namer
```

Update later with `/plugin update`.

Requires `jq` and the `claude` CLI on your `PATH`.

## Configuration

Everything is optional — out of the box you get the format shown above.

| Variable | Default | Purpose |
| --- | --- | --- |
| `SESSION_NAMER_FORMAT` | built-in | Your naming convention, written as prose for the model |
| `SESSION_NAMER_MODEL` | `sonnet` | Model that writes the name |
| `SESSION_NAMER_DISABLE` | unset | Set to anything to turn the plugin off |
| `SESSION_NAMER_CLAUDE_BIN` | `claude` on `PATH` | CLI used to write the name |

> **Running under QoderCLI?** Its models are named differently — there is no
> `sonnet`. Use the `Efficient` tier, and point the plugin at `qodercli` so it
> does not pick up a `claude` binary that happens to be on your `PATH`:
>
> ```json
> { "env": { "SESSION_NAMER_MODEL": "Efficient", "SESSION_NAMER_CLAUDE_BIN": "qodercli" } }
> ```
>
> `qodercli --list-models` shows the rest (`Auto`, `Ultimate`, `Performance`,
> `Efficient`, `Lite`).

Set these in `env` in your `settings.json`:

```json
{
  "env": {
    "SESSION_NAMER_FORMAT": "Format: <area>: <what changed>, in English, max 6 words, lowercase."
  }
}
```

For a per-project convention, write it to `.claude/session-name.md` instead — the
environment variable wins if both are present:

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

A session's title lives in its transcript as a JSONL line:

```json
{"type":"custom-title","customTitle":"…","sessionId":"…"}
```

Claude Code reads the *last* such line, so appending one renames the session —
this is the same mechanism `/rename` uses.

The plugin registers two hooks:

- **`UserPromptSubmit`** — names the session from your first prompt.
- **`SessionStart`** — covers resumed sessions, recovering the topic from the
  opening turns of the existing transcript.

Both run with `async: true`, so the model call never blocks your turn.

A session is named **once**. If a title already exists — set by this plugin, by
`/rename`, or by a previous run — it is left alone. A name that does not match the
active convention is discarded rather than written.

## Notes

- The nested `claude -p` call would re-trigger these hooks, so the script guards
  against recursion with `SESSION_NAMER_RUNNING`.
- Nothing is sent anywhere except the model call that writes the name, and only
  your opening prompt is included in it.

## License

MIT
