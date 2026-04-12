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
cp "$SCRIPT_DIR/widgets.conf" "$KIMCHI_DIR/"
cp "$SCRIPT_DIR/quips.json" "$KIMCHI_DIR/"
chmod +x "$KIMCHI_DIR/kimchi.sh"
chmod +x "$KIMCHI_DIR/widgets.sh"

# Copy widgets
cp "$SCRIPT_DIR/widgets/"*.sh "$KIMCHI_DIR/widgets/"

# Copy status line
cp "$SCRIPT_DIR/statusline-command.sh" "$HOME/.claude/statusline-command.sh"

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

echo ""
echo "  Kimchi Buddy installed!"
echo "  Restart Claude Code to see Kimchi in your status line."
echo "  Type /kimchi-help to see all commands."
echo ""
