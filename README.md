# session-namer

Give every Claude Code session a real name, automatically.

Claude Code lists sessions by id and first message, which makes `/resume` a
guessing game. This plugin names each session with a single model call on the
conversation so far, so your session list reads like a changelog:

```
0904｜修复｜登录页刷新token丢失
0904｜功能｜添加会话自动命名钩子
0903｜优化｜批次文字显示
```

The default format is `MMDD｜type｜summary`, in Chinese: the type is one of
功能, 设计, 修复, 优化, 发布, 探索, 文档, 研究, and the summary is at most 10
characters. Any other convention can be configured, see below.

## Install

```
/plugin marketplace add sorrycc/session-namer
/plugin install session-namer@session-namer
```

Update later with `/plugin update`.

Requires `jq` and the `claude` CLI on your `PATH`.

## Configuration

Everything is optional. Out of the box you get the format shown above.

| Variable | Default | Purpose |
| --- | --- | --- |
| `SESSION_NAMER_FORMAT` | built-in | Naming convention, written as prose for the model |
| `SESSION_NAMER_MODEL` | `sonnet` | Model that writes the name |
| `SESSION_NAMER_DISABLE` | unset | Set to any value to turn the plugin off |
| `SESSION_NAMER_CLAUDE_BIN` | `claude` on `PATH` | CLI used to write the name |
| `SESSION_NAMER_MAX_RENAMES` | `3` | How many times the plugin may name one session |
| `SESSION_NAMER_MAX_TURNS` | `20` | Stop trying to name a still-unnamed session after this many turns |

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

QoderCLI names its models differently, so there is no `sonnet`. Use the
`Efficient` tier and point the plugin at `qodercli`, so it does not pick up a
`claude` binary that happens to be on your `PATH`:

```json
{ "env": { "SESSION_NAMER_MODEL": "Efficient", "SESSION_NAMER_CLAUDE_BIN": "qodercli" } }
```

`qodercli --list-models` shows the other tiers. The per-project file is read
from `.qoder/session-name.md` under QoderCLI, with `.claude/` as a fallback.

## How it works

The plugin registers two async hooks, so the model call never blocks your turn:

- **`UserPromptSubmit`** names the session as the conversation takes shape.
- **`SessionStart`** covers resumed sessions, using the existing transcript.

A session's title is the last `{"type":"custom-title"}` line in its transcript.
Appending one renames the session, which is the same mechanism `/rename` uses.
A name you set with `/rename` is never overwritten.

The only network call is the model request. It carries up to the first three
and last three user turns, capped at 2000 characters, plus the current title
and your convention.

### Naming behavior

- A prompt with no task, such as a greeting or a test message, is skipped. The
  session stays unnamed until real work arrives.
- The name reflects the conversation so far, not the single prompt that
  triggered the hook.
- The plugin's own names are provisional. If the work clearly moves on, the name
  is upgraded, up to `SESSION_NAMER_MAX_RENAMES` times. A name that still fits
  is left alone.
- With the built-in format, output that does not match the expected shape is
  discarded. A custom convention is only checked for being non-empty.

```
"hello"                          → (unnamed)
"thanks!"                        → (unnamed)
"重构支付网关的重试逻辑，加上指数退避"    → 0904｜优化｜支付网关重试指数退避
"退避的最大间隔设成 30 秒"           → 0904｜优化｜支付网关重试指数退避   (unchanged)
"先不管支付了，把 CI 迁到 GitHub Actions" → 0904｜优化｜迁移CI到GitHub Actions
```

## Background

Why this exists: https://x.com/chenchengpro/status/2095410400720482506

## License

MIT
