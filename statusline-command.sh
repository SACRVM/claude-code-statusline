#!/usr/bin/env bash
# Claude Code status line — real usage % from Anthropic (Claude Code v2.1.80+).
# Reads rate_limits.{five_hour,seven_day}.used_percentage from stdin JSON,
# which Claude Code sources from https://api.anthropic.com/api/oauth/usage —
# same numbers shown on claude.ai/usage. No self-invented limits.

input=$(cat)
input_c=$(printf '%s' "$input" | tr -d '\n')

# --- JSON extraction helpers (no jq dependency) ---
json_str() {
  printf '%s' "$input_c" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

# Extract a number nested inside a named sub-object: "<parent>": { ... "<child>": N ... }
# Relies on [^}]* to stay within the same JSON object.
json_nested_num() {
  printf '%s' "$input_c" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*{[^}]*\"$2\"[[:space:]]*:[[:space:]]*\([0-9.]*\).*/\1/p" | head -1
}

cwd=$(json_str cwd)
model=$(json_str display_name)
transcript_path=$(json_str transcript_path)

# --- Project basename ---
proj=""
[ -n "$cwd" ] && proj=$(basename "$cwd")

# --- Git branch ---
git_branch=""
[ -n "$cwd" ] && git_branch=$(git -C "$cwd" branch --show-current 2>/dev/null)

# --- Context % ---
# 1) Prefer Claude Code's pre-calculated context_window.used_percentage.
#    context_window appears before rate_limits in the JSON, so the first
#    "used_percentage" match is always the context one — robust to field order
#    inside the object (unlike [^}]* which breaks on nested current_usage).
ctx_pct=$(printf '%s' "$input_c" | grep -oE '"used_percentage"[[:space:]]*:[[:space:]]*[0-9]+(\.[0-9]+)?' | head -1 | sed 's/.*:[[:space:]]*//')
ctx_pct=${ctx_pct%.*}

# 2) Fallback: sum tokens from the transcript's last usage block.
#    Kicks in before Claude Code populates context_window (very early session).
if [ -z "$ctx_pct" ] || [ "$ctx_pct" = "0" ]; then
  if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    ctx_max=$(printf '%s' "$input_c" | sed -n 's/.*"context_window_size"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)
    ctx_max=${ctx_max:-1000000}
    last_usage=$(tac "$transcript_path" 2>/dev/null | grep -m1 '"usage"')
    if [ -n "$last_usage" ]; then
      inp=$(printf '%s' "$last_usage" | sed -n 's/.*"input_tokens":\([0-9]*\).*/\1/p' | head -1)
      out=$(printf '%s' "$last_usage" | sed -n 's/.*"output_tokens":\([0-9]*\).*/\1/p' | head -1)
      cr=$(printf  '%s' "$last_usage" | sed -n 's/.*"cache_read_input_tokens":\([0-9]*\).*/\1/p' | head -1)
      cc=$(printf  '%s' "$last_usage" | sed -n 's/.*"cache_creation_input_tokens":\([0-9]*\).*/\1/p' | head -1)
      ctx_tokens=$(( ${inp:-0} + ${out:-0} + ${cr:-0} + ${cc:-0} ))
      [ "$ctx_tokens" -gt 0 ] && ctx_pct=$(( ctx_tokens * 100 / ctx_max ))
    fi
  fi
fi
ctx_pct=${ctx_pct:-0}

# --- Real rate limits. Absent for API-key users & before first API response. ---
fh_pct=$(json_nested_num five_hour used_percentage)
wk_pct=$(json_nested_num seven_day used_percentage)
fh_reset=$(json_nested_num five_hour resets_at)
wk_reset=$(json_nested_num seven_day resets_at)

# Round floats to ints for display & color thresholds
fh_int=""; [ -n "$fh_pct" ] && fh_int=$(printf '%.0f' "$fh_pct" 2>/dev/null)
wk_int=""; [ -n "$wk_pct" ] && wk_int=$(printf '%.0f' "$wk_pct" 2>/dev/null)

# Time-until-reset formatter — always more precise than a single unit:
#   <1m, 42m, 3h12m, 2d18h, 6d
fmt_reset() {
  local ts=$1 now diff d h m
  [ -z "$ts" ] && return
  now=$(date +%s)
  diff=$(( ts - now ))
  [ "$diff" -lt 0 ] && diff=0
  d=$(( diff / 86400 ))
  h=$(( (diff % 86400) / 3600 ))
  m=$(( (diff % 3600) / 60 ))
  if   [ "$d" -ge 1 ] && [ "$h" -gt 0 ]; then printf '%dd%dh'   "$d" "$h"
  elif [ "$d" -ge 1 ];                   then printf '%dd'      "$d"
  elif [ "$h" -ge 1 ];                   then printf '%dh%dm'   "$h" "$m"
  elif [ "$m" -ge 1 ];                   then printf '%dm'      "$m"
  else                                        printf '<1m'
  fi
}
fh_left=$(fmt_reset "$fh_reset")
wk_left=$(fmt_reset "$wk_reset")

# --- Colors (Catppuccin Mocha, 24-bit truecolor) ---
RESET='\033[0m'
BOLD='\033[1m'
MAUVE='\033[38;2;203;166;247m'
TEAL='\033[38;2;148;226;213m'
OVERLAY1='\033[38;2;127;132;156m'
SURFACE2='\033[38;2;88;91;112m'
GREEN='\033[38;2;166;227;161m'
YELLOW='\033[38;2;249;226;175m'
RED='\033[38;2;243;139;168m'

pct_color() {
  local p=${1:-0}
  if   [ "$p" -ge 80 ]; then printf '%s' "$RED"
  elif [ "$p" -ge 50 ]; then printf '%s' "$YELLOW"
  else                       printf '%s' "$GREEN"
  fi
}

bar() {
  local p=${1:-0} w=${2:-8} fc f e i out
  fc=$(pct_color "$p")
  [ "$p" -lt 0 ]   && p=0
  [ "$p" -gt 100 ] && p=100
  f=$(( p * w / 100 ))
  [ "$p" -gt 0 ] && [ "$f" -eq 0 ] && f=1
  e=$(( w - f ))
  out="${fc}"
  for ((i=0; i<f; i++)); do out="${out}█"; done
  out="${out}${SURFACE2}"
  for ((i=0; i<e; i++)); do out="${out}░"; done
  out="${out}${RESET}"
  printf '%s' "$out"
}

parts=()

[ -n "$proj" ]       && parts+=("$(printf "${MAUVE}${BOLD}%s${RESET}" "$proj")")
[ -n "$git_branch" ] && parts+=("$(printf "${TEAL}%s${RESET}" "$git_branch")")
[ -n "$model" ]      && parts+=("$(printf "${OVERLAY1}%s${RESET}" "$model")")

if [ -n "$ctx_pct" ] && [ "$ctx_pct" -gt 0 ]; then
  c=$(pct_color "$ctx_pct")
  parts+=("$(printf "${OVERLAY1}ctx ${RESET}%s ${c}%d%%${RESET}" "$(bar "$ctx_pct")" "$ctx_pct")")
fi

if [ -n "$fh_int" ]; then
  c=$(pct_color "$fh_int")
  if [ -n "$fh_left" ]; then
    parts+=("$(printf "${OVERLAY1}5h ${RESET}%s ${c}%d%%${RESET} ${OVERLAY1}(%s)${RESET}" "$(bar "$fh_int")" "$fh_int" "$fh_left")")
  else
    parts+=("$(printf "${OVERLAY1}5h ${RESET}%s ${c}%d%%${RESET}" "$(bar "$fh_int")" "$fh_int")")
  fi
fi

if [ -n "$wk_int" ]; then
  c=$(pct_color "$wk_int")
  if [ -n "$wk_left" ]; then
    parts+=("$(printf "${OVERLAY1}wk ${RESET}%s ${c}%d%%${RESET} ${OVERLAY1}(%s)${RESET}" "$(bar "$wk_int")" "$wk_int" "$wk_left")")
  else
    parts+=("$(printf "${OVERLAY1}wk ${RESET}%s ${c}%d%%${RESET}" "$(bar "$wk_int")" "$wk_int")")
  fi
fi

sep="$(printf "${SURFACE2} · ${RESET}")"
result=""
for p in "${parts[@]}"; do
  if [ -z "$result" ]; then result="$p"; else result="${result}${sep}${p}"; fi
done

printf '%b' "$result"
