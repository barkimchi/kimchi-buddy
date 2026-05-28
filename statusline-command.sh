#!/usr/bin/env bash
# Claude Code status line — robbyrussell theme style
# Reads JSON from stdin, outputs a styled status line

input=$(cat)

# Guard: jq must be installed
if ! command -v jq > /dev/null 2>&1; then
  echo "[statusline] jq not found"
  exit 0
fi

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
[ -z "$cwd" ] && cwd="$PWD"
dir=$(basename "$cwd")

# Config file for display preferences
KIMCHI_CONFIG="$HOME/.claude/kimchi/config.json"
show_cwd=true
show_model=true
show_context=true
color_name="orange"

if [ -f "$KIMCHI_CONFIG" ]; then
  show_cwd=$(jq -r 'if .show_cwd == false then "false" else "true" end' "$KIMCHI_CONFIG" 2>/dev/null || echo "true")
  show_model=$(jq -r 'if .show_model == false then "false" else "true" end' "$KIMCHI_CONFIG" 2>/dev/null || echo "true")
  show_context=$(jq -r 'if .show_context == false then "false" else "true" end' "$KIMCHI_CONFIG" 2>/dev/null || echo "true")
  color_name=$(jq -r '.color // "orange"' "$KIMCHI_CONFIG" 2>/dev/null || echo "orange")
fi

# ANSI color from config.
# Supports three forms:
#   - named 8-bit color (orange, blue, ...)
#   - named 24-bit palette color (ember, maroon, ...)
#   - hex literal (#e8853b) — any truecolor value
case "$color_name" in
  orange)  COLOR='\033[38;5;214m' ;;
  blue)    COLOR='\033[38;5;75m' ;;
  green)   COLOR='\033[38;5;114m' ;;
  red)     COLOR='\033[38;5;196m' ;;
  purple)  COLOR='\033[38;5;141m' ;;
  pink)    COLOR='\033[38;5;211m' ;;
  yellow)  COLOR='\033[38;5;220m' ;;
  cyan)    COLOR='\033[38;5;87m' ;;
  white)   COLOR='\033[38;5;255m' ;;
  ember)   COLOR='\033[38;2;232;133;59m' ;;
  maroon)  COLOR='\033[38;2;196;84;84m' ;;
  emerald) COLOR='\033[38;2;52;211;153m' ;;
  gold)    COLOR='\033[38;2;234;179;58m' ;;
  cobalt)  COLOR='\033[38;2;92;140;224m' ;;
  violet)  COLOR='\033[38;2;124;92;224m' ;;
  \#*)
    hex="${color_name#\#}"
    if [[ "$hex" =~ ^[0-9A-Fa-f]{6}$ ]]; then
      r=$((16#${hex:0:2}))
      g=$((16#${hex:2:2}))
      b=$((16#${hex:4:2}))
      COLOR="\033[38;2;${r};${g};${b}m"
    else
      COLOR='\033[38;5;214m'
    fi
    ;;
  *)       COLOR='\033[38;5;214m' ;;
esac
RESET='\033[0m'

# Model name
model=$(echo "$input" | jq -r '.model.display_name // .model.id // "unknown"')

# Context display is now rendered by the `context` widget on the widget row.
# Toggle with /kimchi-show-ctx and /kimchi-clear-ctx.
# The legacy `show_context` config flag is retained but unused; see widgets.conf.
ctx_part=""

# Kimchi Buddy - full ASCII art in statusline (multi-line supported)
# Face priority: pending_milestone > pending_return > pending_hydrate > idle > hungry
#              > stuck_loop > on_a_roll > activity > late_night_rotation > day_rotation
kimchi_face="( ˘▽˘)"
kimchi_state="$HOME/.claude/kimchi/state.json"
if [ -f "$kimchi_state" ]; then
  k_hunger=$(jq -r '.hunger // 0' "$kimchi_state" 2>/dev/null || echo "0")
  k_last_prompt=$(jq -r '.last_prompt_time // 0' "$kimchi_state" 2>/dev/null || echo "0")
  k_prompt_count=$(jq -r '.prompt_count // 0' "$kimchi_state" 2>/dev/null || echo "0")
  k_rapid_count=$(jq -r '.rapid_count // 0' "$kimchi_state" 2>/dev/null || echo "0")
  k_activity=$(jq -r '.current_activity // "none"' "$kimchi_state" 2>/dev/null || echo "none")
  k_activity_streak=$(jq -r '.activity_streak // 0' "$kimchi_state" 2>/dev/null || echo "0")
  k_pending_milestone=$(jq -r '.pending_milestone // ""' "$kimchi_state" 2>/dev/null || echo "")
  k_pending_return=$(jq -r '.pending_return // ""' "$kimchi_state" 2>/dev/null || echo "")
  k_pending_hydrate=$(jq -r '.pending_hydrate // false' "$kimchi_state" 2>/dev/null || echo "false")
  k_now=$(date +%s)
  k_hour=$(date +%-H)
  k_idle=0
  if [ "$k_last_prompt" -gt 0 ] 2>/dev/null; then
    k_idle=$(( k_now - k_last_prompt ))
  fi

  if [ -n "$k_pending_milestone" ] && [ "$k_pending_milestone" != "null" ]; then
    # One-shot milestone face
    case "$k_pending_milestone" in
      1)   kimchi_face="( ◕▽◕)/" ;;
      10)  kimchi_face="( ˘▽˘)b" ;;
      50)  kimchi_face='\( ◕▽◕)/' ;;
      100) kimchi_face='\( ◕▽◕)/✧' ;;
    esac
  elif [ -n "$k_pending_return" ] && [ "$k_pending_return" != "null" ]; then
    # One-shot returning companion face
    case "$k_pending_return" in
      short)    kimchi_face="( ˘▽˘)" ;;
      medium)   kimchi_face="( ᵔᴥᵔ)" ;;
      long)     kimchi_face="( ˘~˘)" ;;
      next_day) kimchi_face="(ᵔᴥᵔ)✧" ;;
    esac
  elif [ "$k_pending_hydrate" = "true" ]; then
    kimchi_face="( ´ω\`)"
  elif [ "$k_idle" -ge 900 ]; then
    kimchi_face="( -_-)"
  elif [ "$k_hunger" -ge 40 ] 2>/dev/null; then
    kimchi_face="( ˘~˘)"
  elif [ "$k_activity_streak" -ge 4 ] 2>/dev/null && [ "$k_activity" != "none" ]; then
    kimchi_face="(・_・?)"
  elif [ "$k_rapid_count" -ge 3 ] 2>/dev/null; then
    kimchi_face="( ◕▽◕)"
  elif [ "$k_activity" != "none" ] && [ -n "$k_activity" ]; then
    case "$k_activity" in
      builder_meta) kimchi_face="(ง ˘▽˘)ง" ;;
      builder)      kimchi_face="( ˘▽˘)b" ;;
      researcher)   kimchi_face="( ˘ᴗ˘)?" ;;
      asker)        kimchi_face="( ◕‿◕)?" ;;
      actor)        kimchi_face="( ◕▽◕)" ;;
    esac
  elif [ "$k_hour" -lt 5 ] 2>/dev/null; then
    case $((k_prompt_count % 4)) in
      0) kimchi_face="( ¬‿¬)" ;;
      1) kimchi_face="( ¬_¬)" ;;
      2) kimchi_face="( -‿-)" ;;
      3) kimchi_face="( ˘‿˘)" ;;
    esac
  else
    case $((k_prompt_count % 12)) in
      0)  kimchi_face="( ˘▽˘)" ;;
      1)  kimchi_face="( ◕‿◕)" ;;
      2)  kimchi_face="( ˘◡˘)" ;;
      3)  kimchi_face="( ᵔ▽ᵔ)" ;;
      4)  kimchi_face="( ˘ᴗ˘)" ;;
      5)  kimchi_face="( ◠‿◠)" ;;
      6)  kimchi_face="( ˘‿˘ )" ;;
      7)  kimchi_face="(•‿•) " ;;
      8)  kimchi_face="( ˘ ³˘)" ;;
      9)  kimchi_face="(｡◕‿◕｡)" ;;
      10) kimchi_face="( ˘ω˘ )" ;;
      11) kimchi_face="( ᵕᴗᵕ )" ;;
    esac
  fi
fi

# Widget output (pipe input JSON so token widget can read context_window data)
widget_output=""
if [ -f "$HOME/.claude/kimchi/widgets.sh" ]; then
  widget_output=$(echo "$input" | bash "$HOME/.claude/kimchi/widgets.sh" render 2>/dev/null || echo "")
fi

# Split widget output into lines
widget_line1=""
widget_extra=""
if [ -n "$widget_output" ]; then
  widget_line1=$(echo "$widget_output" | head -1)
  widget_extra=$(echo "$widget_output" | tail -n +2)
fi
widget_part=""
[ -n "$widget_line1" ] && widget_part="  ${widget_line1}"

# Build info parts based on config
cwd_part=""
[ "$show_cwd" = "true" ] && cwd_part="  $cwd"

model_part=""
[ "$show_model" = "true" ] && model_part="$model"

info_line="${model_part}"

# Multi-line statusline: jar left, info right, compact layout.
# Widget content can legitimately contain `%` (e.g. "50% ctx"), so any
# variable that may include user-rendered text must go through %s — never
# interpolated into the printf format string directly.
printf "${COLOR} ╭~~~~╮%s${RESET}\n" "$cwd_part"
printf "${COLOR} %s  %s${RESET}\n" "$kimchi_face" "$info_line"
printf "${COLOR} ╰~~~~╯%s${RESET}\n" "$widget_part"
# Feet line with extra widget rows (session timer, goal, etc.)
widget_extra_part=""
if [ -n "$widget_extra" ]; then
  # Join extra lines with double space
  widget_extra_part=$(echo "$widget_extra" | tr '\n' ' ' | sed 's/  */ /g')
  [ -n "$widget_extra_part" ] && widget_extra_part="   ${widget_extra_part}"
fi
printf "${COLOR}  ~  ~%s${RESET}\n" "$widget_extra_part"
