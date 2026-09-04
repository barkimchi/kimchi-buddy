#!/usr/bin/env bash
# Kimchi Buddy Installer
# Installs the terminal pet companion and widget framework for Claude Code

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KIMCHI_DIR="$HOME/.claude/kimchi"
COMMANDS_DIR="$HOME/.claude/commands"
SETTINGS_FILE="$HOME/.claude/settings.json"

echo ""
echo "  🌶  Installing Kimchi Buddy..."
echo ""

# Create directories
mkdir -p "$KIMCHI_DIR/widgets"
mkdir -p "$COMMANDS_DIR"

# Copy core files
cp "$SCRIPT_DIR/kimchi.sh" "$KIMCHI_DIR/"
cp "$SCRIPT_DIR/widgets.sh" "$KIMCHI_DIR/"
cp "$SCRIPT_DIR/quips.json" "$KIMCHI_DIR/"
chmod +x "$KIMCHI_DIR/kimchi.sh"
chmod +x "$KIMCHI_DIR/widgets.sh"

# Merge widgets.conf rather than clobber it, so the user's enabled/disabled
# widget choices survive updates. Any widget the repo introduces that the user
# has never seen is inserted right after the same predecessor it follows
# upstream (or appended to the end if that predecessor isn't present).
if [ ! -f "$KIMCHI_DIR/widgets.conf" ]; then
  cp "$SCRIPT_DIR/widgets.conf" "$KIMCHI_DIR/widgets.conf"
  echo "  Created widgets.conf"
else
  user_conf="$KIMCHI_DIR/widgets.conf"
  added=""
  prev=""
  while IFS= read -r raw || [ -n "$raw" ]; do
    bare="${raw#\#}"                       # strip a leading # (disabled marker)
    [ "$bare" = "---" ] && continue        # row separators carry no state
    [ -z "$bare" ] && continue
    # A widget is "known" if the user conf mentions it enabled OR disabled.
    if grep -qE "^#?${bare}$" "$user_conf"; then
      prev="$bare"
      continue
    fi
    # New widget: insert after its upstream predecessor if the user has it,
    # otherwise append. Either way it lands enabled.
    if [ -n "$prev" ] && grep -qE "^#?${prev}$" "$user_conf"; then
      awk -v p="$prev" -v ins="$bare" '
        { print }
        !done && ($0 == p || $0 == "#" p) { print ins; done=1 }
      ' "$user_conf" > "$user_conf.tmp" && mv "$user_conf.tmp" "$user_conf"
    else
      echo "$bare" >> "$user_conf"
    fi
    added="${added:+$added }$bare"
    prev="$bare"
  done < "$SCRIPT_DIR/widgets.conf"
  if [ -n "$added" ]; then
    echo "  widgets.conf: added new widget(s): $added (existing layout preserved)"
  else
    echo "  widgets.conf: layout preserved (no new widgets)"
  fi
fi

# Copy widgets
cp "$SCRIPT_DIR/widgets/"*.sh "$KIMCHI_DIR/widgets/"

# Copy status line
cp "$SCRIPT_DIR/statusline-command.sh" "$HOME/.claude/statusline-command.sh"

# Remove commands retired by the 4-command surface. Older installs still
# have these in ~/.claude/commands and self-update never deletes files, so
# clean them up explicitly.
DEPRECATED_COMMANDS=(
  kimchi-buddy kimchi-pet kimchi-help kimchi-wrong kimchi-update
  kimchi-countdown kimchi-clear-countdown kimchi-records kimchi-highscore
  kimchi-clear-session kimchi-clear-mood kimchi-clear-streak kimchi-clear-tokens
  kimchi-clear-ctx kimchi-clear-cwd kimchi-clear-model
  kimchi-show-session kimchi-show-mood kimchi-show-streak kimchi-show-tokens
  kimchi-show-ctx kimchi-show-cwd kimchi-show-model kimchi-show-countdown
  tint
)
removed_cmds=""
for cmd_name in "${DEPRECATED_COMMANDS[@]}"; do
  if [ -f "$COMMANDS_DIR/${cmd_name}.md" ]; then
    rm -f "$COMMANDS_DIR/${cmd_name}.md"
    removed_cmds="${removed_cmds:+$removed_cmds }$cmd_name"
  fi
done
if [ -n "$removed_cmds" ]; then
  echo "  Retired old commands: $removed_cmds"
fi

# Copy slash commands
cp "$SCRIPT_DIR/commands/"*.md "$COMMANDS_DIR/"

# Define timestamps used by both the fresh-state and migration branches.
# Must be outside the conditional — set -u means even an unused $TODAY
# reference on the migration path crashes the installer.
NOW=$(date +%s)
TODAY=$(date +%Y-%m-%d)

# Initialize state if it doesn't exist
if [ ! -f "$KIMCHI_DIR/state.json" ]; then
  cat > "$KIMCHI_DIR/state.json" << ENDJSON
{
  "hunger": 0,
  "happiness": 80,
  "prompt_count": 0,
  "session_start": $NOW,
  "last_fed": 0,
  "last_pet": 0,
  "last_quip_time": $NOW,
  "last_decay_time": $NOW,
  "last_prompt_time": 0,
  "rapid_count": 0,
  "flow_start": 0,
  "hydration_warned": false,
  "current_activity": "none",
  "activity_streak": 0,
  "lifetime_prompts": 0,
  "milestones_hit": [],
  "pending_milestone": null,
  "pending_return": null,
  "pending_hydrate": false,
  "pending_quip": null,
  "last_quips": {},
  "spice_timestamps": [],
  "streak_days": 1,
  "streak_last_date": "$TODAY",
  "countdowns": [],
  "goal_type": null,
  "goal_target": null,
  "goal_set_at": null,
  "session_tokens_used": 0
}
ENDJSON
  echo "  Created fresh state.json"
else
  # Add widget fields if missing
  TEMP=$(jq '. +
    (if .pending_quip then {} else {pending_quip: null} end) +
    (if .last_quips then {} else {last_quips: {}} end) +
    (if .spice_timestamps then {} else {spice_timestamps: []} end) +
    (if .streak_days then {} else {streak_days: 1} end) +
    (if .streak_last_date then {} else {streak_last_date: "'"$TODAY"'"} end) +
    (if .countdowns then {} else {countdowns: []} end) +
    (if .goal_type then {} else {goal_type: null} end) +
    (if .goal_target then {} else {goal_target: null} end) +
    (if .goal_set_at then {} else {goal_set_at: null} end) +
    (if .session_tokens_used then {} else {session_tokens_used: 0} end)
  ' "$KIMCHI_DIR/state.json")
  echo "$TEMP" > "$KIMCHI_DIR/state.json"
  echo "  Updated existing state.json with widget fields"
fi

# Initialize records if it doesn't exist
if [ ! -f "$KIMCHI_DIR/records.json" ]; then
  cat > "$KIMCHI_DIR/records.json" << 'ENDJSON'
{
  "longest_session_min": 0,
  "most_prompts_session": 0,
  "highest_spice": "mild",
  "longest_streak_days": 0,
  "highest_combo": 0,
  "weekly_tokens": 0,
  "week_start": "",
  "monthly_tokens": 0,
  "month": "",
  "records_updated": ""
}
ENDJSON
  echo "  Created fresh records.json"
fi

# Update settings.json with hooks
if [ -f "$SETTINGS_FILE" ]; then
  # Check if kimchi hooks already exist
  if grep -q "kimchi.sh tick" "$SETTINGS_FILE" 2>/dev/null; then
    # Update existing hook to include widgets
    if ! grep -q "widgets.sh tick" "$SETTINGS_FILE" 2>/dev/null; then
      TEMP=$(jq '.hooks.UserPromptSubmit[0].hooks[0].command = "bash '"$HOME"'/.claude/kimchi/kimchi.sh tick; bash '"$HOME"'/.claude/kimchi/widgets.sh tick"' "$SETTINGS_FILE")
      echo "$TEMP" > "$SETTINGS_FILE"
      echo "  Updated UserPromptSubmit hook"
    fi
    if ! grep -q "widgets.sh session-end" "$SETTINGS_FILE" 2>/dev/null; then
      TEMP=$(jq '.hooks.SessionStart[0].hooks[0].command = "bash '"$HOME"'/.claude/kimchi/widgets.sh session-end; bash '"$HOME"'/.claude/kimchi/kimchi.sh greet"' "$SETTINGS_FILE")
      echo "$TEMP" > "$SETTINGS_FILE"
      echo "  Updated SessionStart hook"
    fi
  else
    # Add kimchi hooks
    TEMP=$(jq '
      .hooks.UserPromptSubmit = [{"matcher": "", "hooks": [{"type": "command", "command": "bash '"$HOME"'/.claude/kimchi/kimchi.sh tick; bash '"$HOME"'/.claude/kimchi/widgets.sh tick", "timeout": 5}]}] |
      .hooks.SessionStart = [{"matcher": "", "hooks": [{"type": "command", "command": "bash '"$HOME"'/.claude/kimchi/widgets.sh session-end; bash '"$HOME"'/.claude/kimchi/kimchi.sh greet", "timeout": 5}]}]
    ' "$SETTINGS_FILE")
    echo "$TEMP" > "$SETTINGS_FILE"
    echo "  Added Kimchi hooks to settings.json"
  fi

  # Set status line command
  TEMP=$(jq '.statusLine = {"type": "command", "command": "bash '"$HOME"'/.claude/statusline-command.sh"}' "$SETTINGS_FILE")
  echo "$TEMP" > "$SETTINGS_FILE"
  echo "  Set status line command"
else
  echo "  WARNING: ~/.claude/settings.json not found. You may need to configure hooks manually."
fi

# Record the installed commit so self-update can detect "already up to date".
# Best-effort: SCRIPT_DIR may not be a git checkout (e.g. tarball install).
if git -C "$SCRIPT_DIR" rev-parse --short HEAD > /dev/null 2>&1; then
  git -C "$SCRIPT_DIR" rev-parse --short HEAD > "$KIMCHI_DIR/.version"
fi

echo ""
echo "  Kimchi Buddy installed!"
echo "  Restart Claude Code to see Kimchi in your status line."
echo "  Type /kimchi help to see all commands."
echo ""
