# High Score / Records System
# Tracks personal bests across sessions.
# Functions prefixed with _records_ are called by the orchestrator directly, not as widget render/tick.

# Spice level ranking for comparison
_spice_rank() {
  case "$1" in
    REAPER) echo 5 ;;
    Ghost)  echo 4 ;;
    HOT)    echo 3 ;;
    Med)    echo 2 ;;
    Mild)   echo 1 ;;
    *)      echo 0 ;;
  esac
}

_spice_from_count() {
  local count="$1"
  if [ "$count" -ge 15 ]; then echo "REAPER"
  elif [ "$count" -ge 10 ]; then echo "Ghost"
  elif [ "$count" -ge 6 ]; then echo "HOT"
  elif [ "$count" -ge 3 ]; then echo "Med"
  else echo "Mild"
  fi
}

# Called on each tick to check in-session records (spice, combo)
_records_check_tick() {
  if [ ! -f "$RECORDS_FILE" ]; then
    return 0
  fi

  local records
  records=$(cat "$RECORDS_FILE")

  local updated=false
  local new_records="$records"

  # Check spice level
  local spice_window=600
  local cutoff=$(( W_NOW - spice_window ))
  local spice_count
  spice_count=$(jq --argjson cutoff "$cutoff" \
    '[(.spice_timestamps // [])[] | select(. > $cutoff)] | length' "$STATE_FILE" 2>/dev/null || echo "0")
  local current_spice
  current_spice=$(_spice_from_count "$spice_count")
  local current_rank
  current_rank=$(_spice_rank "$current_spice")
  local record_spice
  record_spice=$(echo "$records" | jq -r '.highest_spice // "mild"' 2>/dev/null || echo "mild")
  # Capitalize for ranking comparison
  local record_rank
  case "$record_spice" in
    REAPER) record_rank=5 ;;
    Ghost)  record_rank=4 ;;
    HOT)    record_rank=3 ;;
    Med)    record_rank=2 ;;
    *)      record_rank=1 ;;
  esac
  if [ "$current_rank" -gt "$record_rank" ]; then
    new_records=$(echo "$new_records" | jq --arg spice "$current_spice" '.highest_spice = $spice')
    updated=true
  fi

  # Check combo (rapid_count)
  local rapid
  rapid=$(jq -r '.rapid_count // 0' "$STATE_FILE" 2>/dev/null || echo "0")
  local record_combo
  record_combo=$(echo "$records" | jq -r '.highest_combo // 0' 2>/dev/null || echo "0")
  if [ "$rapid" -gt "$record_combo" ] 2>/dev/null; then
    new_records=$(echo "$new_records" | jq --argjson combo "$rapid" '.highest_combo = $combo')
    updated=true
  fi

  # Check streak
  local streak
  streak=$(jq -r '.streak_days // 0' "$STATE_FILE" 2>/dev/null || echo "0")
  local record_streak
  record_streak=$(echo "$records" | jq -r '.longest_streak_days // 0' 2>/dev/null || echo "0")
  if [ "$streak" -gt "$record_streak" ] 2>/dev/null; then
    new_records=$(echo "$new_records" | jq --argjson s "$streak" '.longest_streak_days = $s')
    updated=true
  fi

  if [ "$updated" = true ]; then
    local now_iso
    now_iso=$(date -u +"%Y-%m-%dT%H:%M:%S")
    new_records=$(echo "$new_records" | jq --arg ts "$now_iso" '.records_updated = $ts')
    echo "$new_records" > "$RECORDS_FILE"
  fi
}

# Called at session start (before greet) to finalize previous session records
_records_session_end() {
  if [ ! -f "$RECORDS_FILE" ] || [ ! -f "$STATE_FILE" ]; then
    return 0
  fi

  local records
  records=$(cat "$RECORDS_FILE")
  local state
  state=$(cat "$STATE_FILE")

  local updated=false
  local new_records="$records"

  # Check session duration
  local session_start last_prompt
  session_start=$(echo "$state" | jq -r '.session_start // 0' 2>/dev/null || echo "0")
  last_prompt=$(echo "$state" | jq -r '.last_prompt_time // 0' 2>/dev/null || echo "0")
  if [ "$session_start" -gt 0 ] && [ "$last_prompt" -gt "$session_start" ] 2>/dev/null; then
    local duration_min=$(( (last_prompt - session_start) / 60 ))
    local record_session
    record_session=$(echo "$records" | jq -r '.longest_session_min // 0' 2>/dev/null || echo "0")
    if [ "$duration_min" -gt "$record_session" ] 2>/dev/null; then
      new_records=$(echo "$new_records" | jq --argjson d "$duration_min" '.longest_session_min = $d')
      updated=true
    fi
  fi

  # Check prompt count
  local prompts
  prompts=$(echo "$state" | jq -r '.prompt_count // 0' 2>/dev/null || echo "0")
  local record_prompts
  record_prompts=$(echo "$records" | jq -r '.most_prompts_session // 0' 2>/dev/null || echo "0")
  if [ "$prompts" -gt "$record_prompts" ] 2>/dev/null; then
    new_records=$(echo "$new_records" | jq --argjson p "$prompts" '.most_prompts_session = $p')
    updated=true
  fi

  # Accumulate token usage from previous session
  local session_tokens
  session_tokens=$(echo "$state" | jq -r '.session_tokens_used // 0' 2>/dev/null || echo "0")
  if [ "$session_tokens" -gt 0 ] 2>/dev/null; then
    local today
    today=$(date +%Y-%m-%d)
    local this_month
    this_month=$(date +%Y-%m)
    # Compute week start (Monday) using macOS date
    local week_start
    local dow
    dow=$(date +%u)  # 1=Monday, 7=Sunday
    local days_since_monday=$(( dow - 1 ))
    week_start=$(date -v-${days_since_monday}d +%Y-%m-%d)

    local rec_week_start
    rec_week_start=$(echo "$records" | jq -r '.week_start // ""' 2>/dev/null || echo "")
    local rec_month
    rec_month=$(echo "$records" | jq -r '.month // ""' 2>/dev/null || echo "")

    # Weekly: reset if new week, else accumulate
    if [ "$rec_week_start" = "$week_start" ]; then
      new_records=$(echo "$new_records" | jq --argjson t "$session_tokens" '.weekly_tokens = ((.weekly_tokens // 0) + $t)')
    else
      new_records=$(echo "$new_records" | jq --argjson t "$session_tokens" --arg ws "$week_start" \
        '.weekly_tokens = $t | .week_start = $ws')
    fi

    # Monthly: reset if new month, else accumulate
    if [ "$rec_month" = "$this_month" ]; then
      new_records=$(echo "$new_records" | jq --argjson t "$session_tokens" '.monthly_tokens = ((.monthly_tokens // 0) + $t)')
    else
      new_records=$(echo "$new_records" | jq --argjson t "$session_tokens" --arg m "$this_month" \
        '.monthly_tokens = $t | .month = $m')
    fi

    updated=true
  fi

  if [ "$updated" = true ]; then
    local now_iso
    now_iso=$(date -u +"%Y-%m-%dT%H:%M:%S")
    new_records=$(echo "$new_records" | jq --arg ts "$now_iso" '.records_updated = $ts')
    echo "$new_records" > "$RECORDS_FILE"
  fi
}

# Display formatted records board
_records_display() {
  if [ ! -f "$RECORDS_FILE" ]; then
    echo "No records yet. Start coding!"
    return 0
  fi

  local r
  r=$(cat "$RECORDS_FILE")

  local session=$(echo "$r" | jq -r '.longest_session_min // 0')
  local prompts=$(echo "$r" | jq -r '.most_prompts_session // 0')
  local spice=$(echo "$r" | jq -r '.highest_spice // "mild"')
  local streak=$(echo "$r" | jq -r '.longest_streak_days // 0')
  local combo=$(echo "$r" | jq -r '.highest_combo // 0')
  local weekly=$(echo "$r" | jq -r '.weekly_tokens // 0')
  local monthly=$(echo "$r" | jq -r '.monthly_tokens // 0')
  local updated=$(echo "$r" | jq -r '.records_updated // "never"')

  # Format session duration nicely
  local session_display
  if [ "$session" -ge 60 ]; then
    local h=$(( session / 60 ))
    local m=$(( session % 60 ))
    session_display="${h}h ${m}m"
  else
    session_display="${session}m"
  fi

  # Format token counts
  local weekly_display
  weekly_display=$(_tokens_format "$weekly")
  local monthly_display
  monthly_display=$(_tokens_format "$monthly")

  printf '\n'
  printf '+-----------------------------+\n'
  printf '|     KIMCHI HIGH SCORES      |\n'
  printf '+-----------------------------+\n'
  printf '|  Longest Session  %-9s|\n' "$session_display"
  printf '|  Most Prompts     %-9s|\n' "$prompts"
  printf '|  Highest Spice    %-9s|\n' "$spice"
  printf '|  Longest Streak   %-9s|\n' "${streak}d"
  printf '|  Highest Combo    %-9s|\n' "x${combo}"
  printf '+-----------------------------+\n'
  printf '|  Weekly Tokens    %-9s|\n' "$weekly_display"
  printf '|  Monthly Tokens   %-9s|\n' "$monthly_display"
  printf '+-----------------------------+\n'
  printf '\n'
  printf 'Last updated: %s\n' "$updated"
}
