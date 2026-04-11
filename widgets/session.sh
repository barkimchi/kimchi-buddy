# Session Timer Widget
# Shows how long the current session has been running.

widget_session_render() {
  local session_start
  session_start=$(echo "$W_STATE" | jq -r '.session_start // 0' 2>/dev/null || echo "0")

  if [ "$session_start" -le 0 ] 2>/dev/null; then
    return 0
  fi

  local elapsed=$(( W_NOW - session_start ))
  local display

  local total_min=$(( elapsed / 60 ))

  if [ "$elapsed" -ge 3600 ]; then
    local h=$(( elapsed / 3600 ))
    local m=$(( (elapsed % 3600) / 60 ))
    display="${total_min} min (${h}hr ${m}min)"
  else
    display="${total_min} min"
  fi

  printf 'Session: %s' "$display"
}
