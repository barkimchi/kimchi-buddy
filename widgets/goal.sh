# Session Goal Widget
# Set a target for the session (prompts or duration) and track progress.

widget_goal_render() {
  local goal_type
  goal_type=$(echo "$W_STATE" | jq -r '.goal_type // empty' 2>/dev/null || echo "")

  if [ -z "$goal_type" ]; then
    return 0
  fi

  local goal_target
  goal_target=$(echo "$W_STATE" | jq -r '.goal_target // 0' 2>/dev/null || echo "0")

  if [ "$goal_target" -le 0 ] 2>/dev/null; then
    return 0
  fi

  local current display_current display_target
  if [ "$goal_type" = "prompts" ]; then
    current=$(echo "$W_STATE" | jq -r '.prompt_count // 0' 2>/dev/null || echo "0")
    display_current="$current"
    display_target="$goal_target"
  else
    # duration goal, target is in minutes
    local session_start
    session_start=$(echo "$W_STATE" | jq -r '.session_start // 0' 2>/dev/null || echo "0")
    local elapsed_min=$(( (W_NOW - session_start) / 60 ))
    current="$elapsed_min"
    display_current="${elapsed_min}m"
    # Format target nicely
    if [ "$goal_target" -ge 60 ]; then
      local h=$(( goal_target / 60 ))
      local m=$(( goal_target % 60 ))
      if [ "$m" -gt 0 ]; then
        display_target="${h}h${m}m"
      else
        display_target="${h}h"
      fi
    else
      display_target="${goal_target}m"
    fi
  fi

  # Check if goal is complete
  if [ "$current" -ge "$goal_target" ] 2>/dev/null; then
    printf 'Goal:DONE'
    return 0
  fi

  # Build mini progress bar [####----] (8 chars wide)
  local bar_width=8
  local filled=$(( current * bar_width / goal_target ))
  if [ "$filled" -gt "$bar_width" ]; then
    filled=$bar_width
  fi
  local empty=$(( bar_width - filled ))
  local bar=""
  local i=0
  while [ "$i" -lt "$filled" ]; do
    bar="${bar}#"
    i=$(( i + 1 ))
  done
  i=0
  while [ "$i" -lt "$empty" ]; do
    bar="${bar}-"
    i=$(( i + 1 ))
  done

  printf 'Goal:%s/%s[%s]' "$display_current" "$display_target" "$bar"
}

widget_goal_set() {
  local gtype="${1:-}"
  local gtarget="${2:-}"
  echo "Goal set: ${gtarget} ${gtype}."
}

widget_goal_clear() {
  echo "Goal cleared."
}
