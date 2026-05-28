# Context Widget
# Renders a compact context-usage bar + percentage on the status line.
# Bar fill and label both track USED context (both grow together toward compaction).
# Reads context window data from status line stdin JSON.

widget_context_render() {
  # Need W_INPUT (status line JSON) for context window data
  if [ -z "$W_INPUT" ]; then
    return 0
  fi

  local remaining_pct
  remaining_pct=$(echo "$W_INPUT" | jq -r '.context_window.remaining_percentage // empty' 2>/dev/null || echo "")

  if [ -z "$remaining_pct" ]; then
    return 0
  fi

  # USED is what we display. Both bar fill and label grow with consumption.
  local rounded used bar_width filled empty fill_char bar i
  rounded=$(printf '%.0f' "$remaining_pct")
  used=$(( 100 - rounded ))
  [ "$used" -lt 0 ] && used=0
  [ "$used" -gt 100 ] && used=100

  bar_width=8
  filled=$(( used * bar_width / 100 ))
  [ "$filled" -gt "$bar_width" ] && filled=$bar_width
  empty=$(( bar_width - filled ))

  # Block density signals urgency within theme color (no inline ANSI).
  if [ "$used" -ge 80 ]; then
    fill_char='█'
  elif [ "$used" -ge 50 ]; then
    fill_char='▓'
  else
    fill_char='▒'
  fi

  bar=""
  i=0
  while [ "$i" -lt "$filled" ]; do bar="${bar}${fill_char}"; i=$((i+1)); done
  i=0
  while [ "$i" -lt "$empty" ]; do bar="${bar}░"; i=$((i+1)); done

  printf '[%s] %d%% ctx' "$bar" "$used"
}
