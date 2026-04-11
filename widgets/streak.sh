# Streak Counter Widget
# Tracks consecutive days the user opened Claude Code.

widget_streak_tick() {
  local today
  today=$(date +%Y-%m-%d)
  local yesterday
  yesterday=$(date -v-1d +%Y-%m-%d)

  local last_date
  last_date=$(echo "$W_STATE" | jq -r '.streak_last_date // ""' 2>/dev/null || echo "")

  if [ "$last_date" = "$today" ]; then
    # Same day, no change
    return 0
  elif [ "$last_date" = "$yesterday" ]; then
    # Consecutive day, increment
    w_update_state --arg today "$today" \
      '.streak_days = ((.streak_days // 0) + 1) | .streak_last_date = $today'
  else
    # Gap or first run, reset to 1
    w_update_state --arg today "$today" \
      '.streak_days = 1 | .streak_last_date = $today'
  fi
}

widget_streak_render() {
  local days
  days=$(echo "$W_STATE" | jq -r '.streak_days // 1' 2>/dev/null || echo "1")
  printf '🔥 %sd' "$days"
}
