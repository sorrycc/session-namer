#!/usr/bin/env bash
# session-namer — give every Claude Code session a real name, automatically.
#
# The session title is stored in the session transcript as a JSONL line:
#   {"type":"custom-title","customTitle":"...","sessionId":"..."}
# Claude Code re-reads the last such line, so appending one renames the session.
#
# Runs async from SessionStart and UserPromptSubmit.
#
# A session opening with "hi" should not be called "greeting" forever, so:
#   - a prompt carrying no task is skipped, and naming waits for real work;
#   - the name is fed the conversation so far, not just one prompt;
#   - the plugin's own names stay provisional and may be upgraded a few times
#     as the work takes shape. A name you set with /rename is never touched.
#
# Configuration (all optional):
#   SESSION_NAMER_DISABLE=1      turn the plugin off
#   SESSION_NAMER_MODEL=haiku    model used to write the name (default: sonnet)
#   SESSION_NAMER_CLAUDE_BIN=... CLI used to write the name (default: claude on PATH)
#   SESSION_NAMER_FORMAT="..."   your naming convention, in prose, for the model
#   .claude/session-name.md      same thing, per project (overridden by the env var)
#   SESSION_NAMER_MAX_RENAMES=3  how many times the plugin may name one session
#   SESSION_NAMER_MAX_TURNS=20   stop trying to name a session after this many turns
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
MAX_RENAMES="${SESSION_NAMER_MAX_RENAMES:-3}"
MAX_TURNS="${SESSION_NAMER_MAX_TURNS:-20}"

payload=$(cat)
transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty')
session_id=$(printf '%s' "$payload" | jq -r '.session_id // empty')
prompt=$(printf '%s' "$payload" | jq -r '.prompt // empty')
project_dir=$(printf '%s' "$payload" | jq -r '.cwd // empty')

[ -n "$transcript" ] && [ -n "$session_id" ] && [ -f "$transcript" ] || exit 0

# --- Who owns the current name? -------------------------------------------
#
# Claude Code re-appends its own {"type":"custom-title"} line as session
# metadata, and that copy does not carry our marker — so ownership cannot be
# read off the last line alone. Instead: collect every title this plugin has
# written (marked with "sessionNamer":true) and compare by value. If the
# effective title is not one of ours, a human set it and we stop.
title_lines=$(grep '"type":"custom-title"' "$transcript" 2>/dev/null)
current_title=$(printf '%s\n' "$title_lines" | tail -n 1 | jq -r '.customTitle // empty' 2>/dev/null)
our_titles=$(printf '%s\n' "$title_lines" | jq -r 'select(.sessionNamer == true) | .customTitle // empty' 2>/dev/null)
our_renames=$(printf '%s\n' "$our_titles" | grep -c '[^[:space:]]')

if [ -n "$current_title" ]; then
  printf '%s\n' "$our_titles" | grep -qxF "$current_title" || exit 0   # renamed by hand
  [ "$our_renames" -ge "$MAX_RENAMES" ] && exit 0                      # budget spent
fi

# --- What is this session about? ------------------------------------------
#
# Name from the conversation so far, not just the prompt that happened to
# trigger the hook. UserPromptSubmit fires before the prompt reaches the
# transcript, so it is appended separately.
turns=$(jq -sc '
  [ .[]
    | select(.type == "user" and (.isSidechain != true))
    | .message.content
    | if type == "string" then . else ([.[]? | select(.type == "text") | .text] | join(" ")) end
  ]
  | map(select(. != null and . != "" and (startswith("<") | not)))
' "$transcript" 2>/dev/null)
[ -n "$turns" ] || turns='[]'

turn_count=$(printf '%s' "$turns" | jq 'length' 2>/dev/null || echo 0)
[ -n "$prompt" ] && turn_count=$((turn_count + 1))

# An unnamed session this far along is not going to get a useful name; stop
# spending a model call on every prompt.
[ -z "$current_title" ] && [ "$turn_count" -gt "$MAX_TURNS" ] && exit 0

topic=$(printf '%s' "$turns" | jq -r --arg p "$prompt" '
  (. + (if $p == "" then [] else [$p] end))
  | if length > 6 then (.[0:3] + .[-3:]) else . end
  | join("\n---\n")
' 2>/dev/null)

topic=$(printf '%s' "$topic" | head -c 2000)
[ -n "$topic" ] || exit 0

# --- Naming convention: env var > per-project file > built-in default ------
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

if [ -n "$current_title" ]; then
  standing="This session is currently named: $current_title
Output a new name ONLY if the work has clearly moved on from that name.
If the current name still fits, output exactly: SKIP"
else
  standing="If the conversation carries no identifiable task yet — a greeting, a
thank-you, a test message, small talk — output exactly: SKIP"
fi

read -r -d '' instructions <<EOF
Name this Claude Code session. Today is $(date +%Y-%m-%d).
Output ONLY the name — no explanation, no quotes, no surrounding punctuation, one line.

$standing

$convention

The conversation so far:
<conversation>
$topic
</conversation>
EOF

name=$("$CLAUDE_BIN" -p --model "$MODEL" "$instructions" 2>/dev/null \
  | tr -d '\r`"' \
  | grep -m1 '[^[:space:]]' \
  | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
  | head -c 120)

# The model declined — no task yet, or the standing name still fits.
case "$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]' | tr -d '[:punct:][:space:]')" in
  SKIP) exit 0 ;;
esac

# Validate. The built-in convention has a known shape, so check it strictly;
# a custom convention can be anything, so only sanity-check it.
if [ "$builtin_default" = 1 ]; then
  printf '%s' "$name" | grep -qE '^[0-9]{4}｜(功能|设计|修复|优化|发布|探索|文档|研究)｜.+$' || exit 0
else
  case "$name" in ''|'<'*) exit 0 ;; esac
fi

[ "$name" = "$current_title" ] && exit 0

# Re-check: the session may have been renamed while the model was thinking.
now_lines=$(grep '"type":"custom-title"' "$transcript" 2>/dev/null)
now_title=$(printf '%s\n' "$now_lines" | tail -n 1 | jq -r '.customTitle // empty' 2>/dev/null)
if [ -n "$now_title" ] && [ "$now_title" != "$current_title" ]; then
  printf '%s\n' "$now_lines" | jq -r 'select(.sessionNamer == true) | .customTitle // empty' 2>/dev/null \
    | grep -qxF "$now_title" || exit 0
fi

# Keep the JSONL well-formed if a previous write was cut short.
[ -s "$transcript" ] && [ "$(tail -c 1 "$transcript")" != "" ] && printf '\n' >> "$transcript"
jq -nc --arg t "$name" --arg s "$session_id" \
  '{type:"custom-title",customTitle:$t,sessionId:$s,sessionNamer:true}' >> "$transcript"
