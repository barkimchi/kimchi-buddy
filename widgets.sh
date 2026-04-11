#!/usr/bin/env bash
# Kimchi Buddy Widget Orchestrator
# Usage: widgets.sh <mode> [args]
#
# Modes:
#   tick              Update widget state (called by UserPromptSubmit hook)
#   render            Output widget display strings (called by status line)
#   session-end       Finalize records from previous session (called by SessionStart hook)
#   countdown-set     Add a countdown: widgets.sh countdown-set <label> <seconds_from_now>
#   countdown-list    List active countdowns
#   countdown-remove  Remove a countdown: widgets.sh countdown-remove <label>
#   goal-set          Set session goal: widgets.sh goal-set <type> <target>
#   goal-clear        Clear current goal
#   records           Display high score board

set -euo pipefail

# Allow override for testing
KIMCHI_DIR="${KIMCHI_STATE_DIR:-$HOME/.claude/kimchi}"
STATE_FILE="${KIMCHI_STATE_FILE:-$KIMCHI_DIR/state.json}"
RECORDS_FILE="$KIMCHI_DIR/records.json"
WIDGETS_DIR="$KIMCHI_DIR/widgets"
CONF_FILE="$KIMCHI_DIR/widgets.conf"

# Shared variables for widgets (exported so sourced files see them)
export W_STATE=""
export W_NOW
export W_INPUT=""
export STATE_FILE
export RECORDS_FILE

W_NOW=$(date +%s)

# Read state once
if [ -f "$STATE_FILE" ]; then
  W_STATE=$(cat "$STATE_FILE")
fi

# Read stdin if available (render mode gets JSON from status line)
if [ ! -t 0 ]; then
  W_INPUT=$(cat 2>/dev/null || echo "{}")
fi

# Helper: atomic jq update on state.json
# Usage: w_update_state [jq_args...] <jq_expression>
# Passes all arguments directly to jq. The last argument is the expression.
w_update_state() {
  if [ -f "$STATE_FILE" ]; then
    local tmp
    tmp=$(jq "$@" "$STATE_FILE")
    echo "$tmp" > "$STATE_FILE"
  fi
}

# Helper: read a field from W_STATE (no file I/O)
w_read() {
  local field="$1"
  echo "$W_STATE" | jq -r ".$field // empty" 2>/dev/null || echo ""
}

# Helper: atomic jq update on records.json
# Usage: w_update_records [jq_args...] <jq_expression>
w_update_records() {
  if [ -f "$RECORDS_FILE" ]; then
    local tmp
    tmp=$(jq "$@" "$RECORDS_FILE")
    echo "$tmp" > "$RECORDS_FILE"
  fi
}

# Collect enabled widget names (--- is a row separator, preserved for render)
WIDGET_NAMES=""
WIDGET_NAMES_FLAT=""
if [ -f "$CONF_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    # Strip comments and whitespace
    name=$(echo "$line" | sed 's/#.*//' | tr -d '[:space:]')
    [ -z "$name" ] && continue
    WIDGET_NAMES="${WIDGET_NAMES}${WIDGET_NAMES:+ }${name}"
    if [ "$name" != "---" ]; then
      WIDGET_NAMES_FLAT="${WIDGET_NAMES_FLAT}${WIDGET_NAMES_FLAT:+ }${name}"
    fi
  done < "$CONF_FILE"
fi

# Source all enabled widget files (skip row separators)
for name in $WIDGET_NAMES_FLAT; do
  widget_file="$WIDGETS_DIR/${name}.sh"
  if [ -f "$widget_file" ]; then
    . "$widget_file"
  fi
done

# Source records system (not a standard widget, provides _records_* functions)
if [ -f "$WIDGETS_DIR/records.sh" ]; then
  . "$WIDGETS_DIR/records.sh"
fi

MODE="${1:-render}"
shift 2>/dev/null || true

case "$MODE" in
  tick)
    for name in $WIDGET_NAMES_FLAT; do
      fn="widget_${name}_tick"
      if type "$fn" &>/dev/null; then
        "$fn" || true
      fi
    done
    # Update records on each tick (spice, combo)
    if type _records_check_tick &>/dev/null; then
      _records_check_tick || true
    fi
    ;;

  render)
    row=""
    first_row=true
    for name in $WIDGET_NAMES; do
      if [ "$name" = "---" ]; then
        # Row separator: emit current row and start a new one
        if [ -n "$row" ]; then
          if [ "$first_row" = true ]; then
            printf '%s' "$row"
            first_row=false
          else
            printf '\n%s' "$row"
          fi
          row=""
        fi
        continue
      fi
      fn="widget_${name}_render"
      if type "$fn" &>/dev/null; then
        piece=$("$fn" 2>/dev/null || echo "")
        if [ -n "$piece" ]; then
          row="${row}${row:+  }${piece}"
        fi
      fi
    done
    # Emit the last row
    if [ -n "$row" ]; then
      if [ "$first_row" = true ]; then
        printf '%s' "$row"
      else
        printf '\n%s' "$row"
      fi
    fi
    echo ""
    ;;

  session-end)
    if type _records_session_end &>/dev/null; then
      _records_session_end "$@" || true
    fi
    ;;

  countdown-set)
    label="${1:-}"
    seconds="${2:-}"
    if [ -z "$label" ] || [ -z "$seconds" ]; then
      echo "Usage: widgets.sh countdown-set <label> <seconds_from_now>"
      exit 1
    fi
    target_epoch=$(( W_NOW + seconds ))
    w_update_state --argjson target "$target_epoch" --arg label "$label" \
      '.countdowns = ((.countdowns // []) | map(select(.label != $label))) + [{"label": $label, "target_epoch": $target}]'
    echo "Countdown '$label' set for ${seconds}s from now."
    ;;

  countdown-list)
    if type widget_countdown_list &>/dev/null; then
      widget_countdown_list
    else
      echo "Countdown widget not loaded."
    fi
    ;;

  countdown-remove)
    label="${1:-}"
    if [ -z "$label" ]; then
      echo "Usage: widgets.sh countdown-remove <label>"
      exit 1
    fi
    w_update_state --arg label "$label" \
      '.countdowns = ((.countdowns // []) | map(select(.label != $label)))'
    echo "Countdown '$label' removed."
    ;;

  countdown-remove-all)
    w_update_state '.countdowns = []'
    echo "All countdowns cleared."
    ;;

  session-reset)
    w_update_state --argjson now "$W_NOW" '.session_start = $now'
    echo "Session timer reset."
    ;;

  goal-set)
    gtype="${1:-}"
    gtarget="${2:-}"
    if [ -z "$gtype" ] || [ -z "$gtarget" ]; then
      echo "Usage: widgets.sh goal-set <prompts|duration> <target>"
      exit 1
    fi
    w_update_state --arg gtype "$gtype" --argjson gtarget "$gtarget" --argjson now "$W_NOW" \
      '.goal_type = $gtype | .goal_target = $gtarget | .goal_set_at = $now'
    if [ "$gtype" = "prompts" ]; then
      echo "Goal set: $gtarget prompts this session."
    else
      echo "Goal set: ${gtarget}m this session."
    fi
    ;;

  goal-clear)
    w_update_state '.goal_type = null | .goal_target = null | .goal_set_at = null'
    echo "Goal cleared."
    ;;

  records)
    if type _records_display &>/dev/null; then
      _records_display
    else
      echo "Records system not loaded."
    fi
    ;;

  *)
    echo "Unknown mode: $MODE"
    echo "Usage: widgets.sh <tick|render|session-end|countdown-set|countdown-list|countdown-remove|goal-set|goal-clear|records>"
    exit 1
    ;;
esac
