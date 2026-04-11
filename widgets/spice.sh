# Spice Meter Widget
# Tracks session intensity based on prompt frequency over a rolling 10-min window.
# Escalates: Mild -> Medium -> Hot -> Ghost -> REAPER

SPICE_WINDOW=600  # 10 minutes in seconds

widget_spice_tick() {
  local cutoff=$(( W_NOW - SPICE_WINDOW ))
  w_update_state --argjson now "$W_NOW" --argjson cutoff "$cutoff" \
    '.spice_timestamps = ((.spice_timestamps // []) | map(select(. > $cutoff))) + [$now]'
}

widget_spice_render() {
  local cutoff=$(( W_NOW - SPICE_WINDOW ))
  local count
  count=$(echo "$W_STATE" | jq --argjson cutoff "$cutoff" \
    '[(.spice_timestamps // [])[] | select(. > $cutoff)] | length' 2>/dev/null || echo "0")

  local label
  if [ "$count" -ge 15 ]; then
    label="REAPER"
  elif [ "$count" -ge 10 ]; then
    label="Ghost"
  elif [ "$count" -ge 6 ]; then
    label="HOT"
  elif [ "$count" -ge 3 ]; then
    label="Med"
  else
    label="Mild"
  fi
  printf '🌶  %s' "$label"
}
