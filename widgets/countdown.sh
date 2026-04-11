# Countdown Widget
# Set timers that tick down in the status line.
# Managed via /countdown slash command or widgets.sh countdown-set/list/remove.

widget_countdown_render() {
  # Prune expired countdowns and show the nearest active one
  local active
  active=$(echo "$W_STATE" | jq --argjson now "$W_NOW" \
    '[(.countdowns // [])[] | select(.target_epoch > $now)] | sort_by(.target_epoch) | first // empty' 2>/dev/null || echo "")

  if [ -z "$active" ]; then
    return 0
  fi

  local label target_epoch remaining
  label=$(echo "$active" | jq -r '.label' 2>/dev/null || echo "")
  target_epoch=$(echo "$active" | jq -r '.target_epoch' 2>/dev/null || echo "0")
  remaining=$(( target_epoch - W_NOW ))

  if [ "$remaining" -le 0 ]; then
    return 0
  fi

  local display
  if [ "$remaining" -ge 3600 ]; then
    local hours=$(( remaining / 3600 ))
    local mins=$(( (remaining % 3600) / 60 ))
    display="${hours}h${mins}m"
  else
    local mins=$(( remaining / 60 ))
    display="${mins}m"
  fi

  printf '%s:%s' "$label" "$display"
}

widget_countdown_list() {
  local countdowns
  countdowns=$(echo "$W_STATE" | jq -r '.countdowns // []' 2>/dev/null || echo "[]")
  local count
  count=$(echo "$countdowns" | jq 'length' 2>/dev/null || echo "0")

  if [ "$count" -eq 0 ]; then
    echo "No active countdowns."
    return 0
  fi

  echo "Active countdowns:"
  echo ""
  echo "$countdowns" | jq -r --argjson now "$W_NOW" '.[] |
    if .target_epoch > $now then
      "  \(.label): \(((.target_epoch - $now) / 60 | floor))m remaining"
    else
      "  \(.label): EXPIRED"
    end' 2>/dev/null
}
