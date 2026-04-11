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

# ANSI colors
ORANGE='\033[38;5;214m'
RESET='\033[0m'

# Model name
model=$(echo "$input" | jq -r '.model.display_name // .model.id // "unknown"')

# Context remaining
remaining_pct=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')
ctx_part=""
if [ -n "$remaining_pct" ]; then
  rounded=$(printf '%.0f' "$remaining_pct")
  ctx_part="  ctx: ${rounded}%"
fi

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

# Multi-line statusline: jar left, info right, compact layout
printf "${ORANGE} ╭~~~~╮  %s${RESET}\n" "$cwd"
printf "${ORANGE} %s  %s%s${RESET}\n" "$kimchi_face" "$model" "$ctx_part"
printf "${ORANGE} ╰~~~~╯${widget_part}${RESET}\n"
# Feet line with extra widget rows (session timer, goal, etc.)
widget_extra_part=""
if [ -n "$widget_extra" ]; then
  # Join extra lines with double space
  widget_extra_part=$(echo "$widget_extra" | tr '\n' ' ' | sed 's/  */ /g')
  [ -n "$widget_extra_part" ] && widget_extra_part="   ${widget_extra_part}"
fi
printf "${ORANGE}  ~  ~${widget_extra_part}${RESET}\n"
