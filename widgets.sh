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

  widget-disable)
    wname="${1:-}"
    if [ -z "$wname" ]; then
      echo "Usage: widgets.sh widget-disable <widget_name>"
      exit 1
    fi
    if grep -q "^${wname}$" "$CONF_FILE" 2>/dev/null; then
      sed -i '' "s/^${wname}$/#${wname}/" "$CONF_FILE"
      echo "${wname} disabled."
    else
      echo "${wname} is already disabled or not found."
    fi
    ;;

  widget-enable)
    wname="${1:-}"
    if [ -z "$wname" ]; then
      echo "Usage: widgets.sh widget-enable <widget_name>"
      exit 1
    fi
    if grep -q "^#${wname}$" "$CONF_FILE" 2>/dev/null; then
      sed -i '' "s/^#${wname}$/${wname}/" "$CONF_FILE"
      echo "${wname} enabled."
    elif grep -q "^${wname}$" "$CONF_FILE" 2>/dev/null; then
      echo "${wname} is already enabled."
    else
      echo "$wname" >> "$CONF_FILE"
      echo "${wname} added and enabled."
    fi
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

  config-set)
    key="${1:-}"
    val="${2:-}"
    if [ -z "$key" ] || [ -z "$val" ]; then
      echo "Usage: widgets.sh config-set <key> <value>"
      exit 1
    fi
    CONFIG_FILE="$KIMCHI_DIR/config.json"
    if [ ! -f "$CONFIG_FILE" ]; then
      echo '{"show_cwd":true,"show_model":true,"show_context":true,"color":"orange"}' > "$CONFIG_FILE"
    fi
    # Detect boolean vs string
    if [ "$val" = "true" ] || [ "$val" = "false" ]; then
      tmp=$(jq --arg k "$key" --argjson v "$val" '.[$k] = $v' "$CONFIG_FILE")
      echo "$tmp" > "$CONFIG_FILE"
    else
      tmp=$(jq --arg k "$key" --arg v "$val" '.[$k] = $v' "$CONFIG_FILE")
      echo "$tmp" > "$CONFIG_FILE"
    fi
    echo "${key} set to ${val}."
    ;;

  config-show)
    CONFIG_FILE="$KIMCHI_DIR/config.json"
    if [ ! -f "$CONFIG_FILE" ]; then
      echo "No config file. Using defaults."
      exit 0
    fi
    cfg=$(cat "$CONFIG_FILE")
    c_cwd=$(echo "$cfg" | jq -r '.show_cwd // true')
    c_model=$(echo "$cfg" | jq -r '.show_model // true')
    c_ctx=$(echo "$cfg" | jq -r '.show_context // true')
    c_color=$(echo "$cfg" | jq -r '.color // "orange"')

    printf '\n'
    printf '+-------------------------------+\n'
    printf '|      KIMCHI SETTINGS          |\n'
    printf '+-------------------------------+\n'
    printf '|  CWD         %-16s|\n' "$c_cwd"
    printf '|  Model       %-16s|\n' "$c_model"
    printf '|  Context     %-16s|\n' "$c_ctx"
    printf '|  Color       %-16s|\n' "$c_color"
    printf '+-------------------------------+\n'
    printf '\n'
    printf 'Colors: orange, blue, green, red,\n'
    printf '        purple, pink, yellow,\n'
    printf '        cyan, white\n'
    ;;

  self-update)
    REPO="https://github.com/barkimchi/kimchi-buddy.git"
    VERSION_FILE="$KIMCHI_DIR/.version"
    TMP_DIR=$(mktemp -d)
    echo "Checking for updates..."
    if git clone --quiet "$REPO" "$TMP_DIR" 2>/dev/null; then
      new_sha=$(git -C "$TMP_DIR" rev-parse --short HEAD 2>/dev/null || echo "")
      old_sha=""
      [ -f "$VERSION_FILE" ] && old_sha=$(cat "$VERSION_FILE" 2>/dev/null || echo "")
      if [ -n "$new_sha" ] && [ "$old_sha" = "$new_sha" ]; then
        echo "Already up to date ($new_sha)."
        rm -rf "$TMP_DIR"
        exit 0
      fi
      # install.sh writes the new SHA to $VERSION_FILE on success.
      bash "$TMP_DIR/install.sh"
      if [ -n "$old_sha" ]; then
        echo "Updated ${old_sha} -> ${new_sha:-latest}."
      else
        echo "Updated to ${new_sha:-latest}."
      fi
      rm -rf "$TMP_DIR"
    else
      echo "Failed to clone repo. Check your internet connection."
      rm -rf "$TMP_DIR"
      exit 1
    fi
    ;;

  *)
    echo "Unknown mode: $MODE"
    exit 1
    ;;
esac
