#!/usr/bin/env bash
# session-namer — give every Claude Code session a real name, automatically.
#
# The session title is stored in the session transcript as a JSONL line:
#   {"type":"custom-title","customTitle":"...","sessionId":"..."}
# Claude Code re-reads the last such line, so appending one renames the session.
#
# Runs async from SessionStart and UserPromptSubmit. A session is named once:
# the first run that produces a valid name wins, and an existing name (yours,
# or one you set with /rename) is never overwritten.
#
# Configuration (all optional):
#   SESSION_NAMER_DISABLE=1      turn the plugin off
#   SESSION_NAMER_MODEL=haiku    model used to write the name (default: sonnet)
#   SESSION_NAMER_CLAUDE_BIN=... CLI used to write the name (default: claude on PATH)
#   SESSION_NAMER_FORMAT="..."   your naming convention, in prose, for the model
#   .claude/session-name.md      same thing, per project (overridden by the env var)
#
# Under QoderCLI the model names differ — there is no `sonnet`. Use the
# `Efficient` tier, and point the plugin at that CLI so it does not pick up a
# `claude` binary that happens to be on PATH:
#   SESSION_NAMER_MODEL=Efficient SESSION_NAMER_CLAUDE_BIN=qodercli

set -uo pipefail

[ -n "${SESSION_NAMER_DISABLE:-}" ] && exit 0

# Guard against recursion: the `claude -p` call below starts a session that
# would otherwise fire these same hooks.
[ -n "${SESSION_NAMER_RUNNING:-}" ] && exit 0
export SESSION_NAMER_RUNNING=1

command -v jq >/dev/null 2>&1 || exit 0
CLAUDE_BIN="${SESSION_NAMER_CLAUDE_BIN:-$(command -v claude)}"
[ -x "$CLAUDE_BIN" ] || exit 0

MODEL="${SESSION_NAMER_MODEL:-sonnet}"

payload=$(cat)
transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty')
session_id=$(printf '%s' "$payload" | jq -r '.session_id // empty')
prompt=$(printf '%s' "$payload" | jq -r '.prompt // empty')
project_dir=$(printf '%s' "$payload" | jq -r '.cwd // empty')

[ -n "$transcript" ] && [ -n "$session_id" ] && [ -f "$transcript" ] || exit 0

# Already named (by us, by /rename, or by a previous run) — leave it alone.
grep -q '"type":"custom-title"' "$transcript" && exit 0

# Prefer the prompt from the hook payload (UserPromptSubmit); otherwise recover
# the opening user turns from the transcript (SessionStart on a resumed session).
topic="$prompt"
if [ -z "$topic" ]; then
  topic=$(jq -rs '
    [ .[]
      | select(.type == "user" and (.isSidechain != true))
      | .message.content
      | if type == "string" then . else ([.[]? | select(.type == "text") | .text] | join(" ")) end
    ]
    | map(select(. != null and . != "" and (startswith("<") | not)))
    | .[0:3] | join("\n")
  ' "$transcript" 2>/dev/null)
fi

topic=$(printf '%s' "$topic" | head -c 2000)
[ -n "$topic" ] || exit 0

# Naming convention: env var > per-project file > built-in default.
convention="${SESSION_NAMER_FORMAT:-}"
if [ -z "$convention" ] && [ -n "$project_dir" ] && [ -f "$project_dir/.claude/session-name.md" ]; then
  convention=$(head -c 2000 "$project_dir/.claude/session-name.md")
fi

builtin_default=0
if [ -z "$convention" ]; then
  builtin_default=1
  convention="Format: $(date +%m%d)｜类型｜摘要
- 分隔符必须是全角竖线 ｜
- 类型从这个列表里选一个：功能 设计 修复 优化 发布 探索 文档 研究
- 摘要用中文，不超过 10 个字，概括这次会话在做什么"
fi

read -r -d '' instructions <<EOF
Name this Claude Code session. Today is $(date +%Y-%m-%d).
Output ONLY the name — no explanation, no quotes, no surrounding punctuation, one line.

$convention

The user's request:
<request>
$topic
</request>
EOF

name=$("$CLAUDE_BIN" -p --model "$MODEL" "$instructions" 2>/dev/null \
  | tr -d '\r`"' \
  | grep -m1 '[^[:space:]]' \
  | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
  | head -c 120)

# Validate. The built-in convention has a known shape, so check it strictly;
# a custom convention can be anything, so only sanity-check it.
if [ "$builtin_default" = 1 ]; then
  printf '%s' "$name" | grep -qE '^[0-9]{4}｜(功能|设计|修复|优化|发布|探索|文档|研究)｜.+$' || exit 0
else
  case "$name" in ''|'<'*) exit 0 ;; esac
fi

# Re-check: the session may have been named while the model was thinking.
grep -q '"type":"custom-title"' "$transcript" && exit 0

# Keep the JSONL well-formed if a previous write was cut short.
[ -s "$transcript" ] && [ "$(tail -c 1 "$transcript")" != "" ] && printf '\n' >> "$transcript"
jq -nc --arg t "$name" --arg s "$session_id" \
  '{type:"custom-title",customTitle:$t,sessionId:$s}' >> "$transcript"
