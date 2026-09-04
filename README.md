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
| `SESSION_NAMER_MAX_RENAMES` | `3` | How many times the plugin may name one session |
| `SESSION_NAMER_MAX_TURNS` | `20` | Give up on a still-unnamed session after this many turns |

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

- **`UserPromptSubmit`** — names the session as the conversation takes shape.
- **`SessionStart`** — covers resumed sessions, recovering the topic from the
  existing transcript.

Both run with `async: true`, so the model call never blocks your turn.

### Opening with "hi" does not name the session "greeting"

Naming waits for actual work, and stays open to revision for a while:

- A prompt carrying no task — a greeting, a thank-you, a test message — is
  **skipped**, and the session stays unnamed until real work arrives.
- The name is written from the **conversation so far**, not from whichever single
  prompt happened to trigger the hook.
- The plugin's own names are **provisional**: if the work clearly moves on, the
  name is upgraded, up to `SESSION_NAMER_MAX_RENAMES` times. A name that still
  fits is left alone, so the title does not churn.

```
"hello"                          → (unnamed)
"thanks!"                        → (unnamed)
"重构支付网关的重试逻辑，加上指数退避"    → 0904｜优化｜支付网关重试指数退避
"退避的最大间隔设成 30 秒"           → 0904｜优化｜支付网关重试指数退避   (unchanged)
"先不管支付了，把 CI 迁到 GitHub Actions" → 0904｜优化｜迁移CI到GitHub Actions
```

A name **you** set with `/rename` is never touched. The plugin marks its own
writes with `"sessionNamer": true` and matches by value, so it can tell its own
name from yours even after Claude Code re-appends the title as session metadata.
A name that does not match the active convention is discarded rather than written.

## Notes

- The nested `claude -p` call would re-trigger these hooks, so the script guards
  against recursion with `SESSION_NAMER_RUNNING`.
- Nothing is sent anywhere except the model call that writes the name, and only
  your opening prompt is included in it.

## License

MIT
