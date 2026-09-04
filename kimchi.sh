#!/usr/bin/env bash
# Kimchi Buddy - Core Engine
# Usage: kimchi.sh <command> [args]
#
# Commands:
#   init        Initialize/resume a session (resets session fields, preserves hunger)

set -euo pipefail

# Allow override for testing
STATE_DIR="${KIMCHI_STATE_DIR:-$HOME/.claude/kimchi}"
STATE_FILE="${KIMCHI_STATE_FILE:-$STATE_DIR/state.json}"
QUIPS_FILE="$STATE_DIR/quips.json"
WRONG_FILE="$STATE_DIR/wrong-reports.json"

now_epoch() { date +%s; }
now_iso() { date -u +"%Y-%m-%dT%H:%M:%S"; }
current_hour() { date +%-H; }

ensure_dir() {
  [ -d "$STATE_DIR" ] || mkdir -p "$STATE_DIR"
}

# Read a field from state.json. Returns empty string if file/field missing.
read_state() {
  local field="$1"
  if [ -f "$STATE_FILE" ]; then
    jq -r ".$field // empty" "$STATE_FILE" 2>/dev/null || echo ""
  else
    echo ""
  fi
}

# Write full state object (pass JSON string)
write_state() {
  local json="$1"
  echo "$json" > "$STATE_FILE"
}

# Update a single field in state
update_field() {
  local field="$1" value="$2"
  if [ -f "$STATE_FILE" ]; then
    local tmp
    tmp=$(jq ".$field = $value" "$STATE_FILE")
    echo "$tmp" > "$STATE_FILE"
  fi
}

# Initialize or resume session.
# Preserves: hunger, happiness, lifetime_prompts, milestones_hit, last_session_end.
# Resets: session_start, prompt_count, last_quip_time, last_decay_time, hydration_warned, current_activity, activity_streak.
cmd_init() {
  ensure_dir
  local now
  now=$(now_epoch)

  if [ -f "$STATE_FILE" ]; then
    # Existing state - reset session-scoped fields, preserve lifetime
    local tmp
    tmp=$(jq \
      --argjson now "$now" \
      '.session_start = $now |
       .prompt_count = 0 |
       .last_quip_time = $now |
       .last_decay_time = $now |
       .hydration_warned = false |
       .current_activity = "none" |
       .activity_streak = 0 |
       .pending_milestone = null |
       .pending_return = null |
       .pending_hydrate = false |
       .pending_quip = null |
       .lifetime_prompts = (.lifetime_prompts // 0) |
       .milestones_hit = (.milestones_hit // [])' \
      "$STATE_FILE")
    echo "$tmp" > "$STATE_FILE"
  else
    # Brand new state
    cat > "$STATE_FILE" << ENDJSON
{
  "hunger": 0,
  "happiness": 80,
  "prompt_count": 0,
  "session_start": $now,
  "last_fed": 0,
  "last_pet": 0,
  "last_quip_time": $now,
  "last_decay_time": $now,
  "lifetime_prompts": 0,
  "milestones_hit": [],
  "current_activity": "none",
  "activity_streak": 0,
  "hydration_warned": false,
  "pending_milestone": null,
  "pending_return": null,
  "pending_hydrate": false,
  "pending_quip": null,
  "last_quips": {},
  "last_session_end": 0
}
ENDJSON
  fi
}

# Select a quip.
# Usage: cmd_quip <fermentation_level> <category>
# fermentation_level: fresh|brined|fermented|extra_fermented|any
# category: general|pet|feed|idle|hungry|<activity>|milestone_*|return_*|hydrate
# "general" uses the fermentation level key. Others use their own key.
# Cycles through the pool in order instead of drawing at random, so every
# quip gets seen and nothing repeats until the whole pool has played.
# Position is remembered per key in state.json (.last_quips).
cmd_quip() {
  local level="${1:-fresh}" category="${2:-general}"
  local key

  if [ "$category" = "general" ]; then
    key="$level"
  else
    key="$category"
  fi

  if [ ! -f "$QUIPS_FILE" ]; then
    echo ""
    return
  fi

  local count
  count=$(jq -r ".[\"$key\"] | length" "$QUIPS_FILE" 2>/dev/null || echo "0")
  case "$count" in ''|*[!0-9]*) count=0 ;; esac
  if [ "$count" -eq 0 ]; then
    echo ""
    return
  fi

  # Advance past the last quip shown for this key. First visit starts at a
  # time-derived offset so two installs don't march in lockstep.
  local last_idx idx
  last_idx=-1
  if [ -f "$STATE_FILE" ]; then
    last_idx=$(jq -r ".last_quips[\"$key\"] // -1" "$STATE_FILE" 2>/dev/null || echo "-1")
    case "$last_idx" in ''|*[!0-9-]*) last_idx=-1 ;; esac
  fi
  if [ "$last_idx" -ge 0 ]; then
    idx=$(( (last_idx + 1) % count ))
  else
    idx=$(( $(now_epoch) % count ))
  fi

  if [ -f "$STATE_FILE" ]; then
    local tmp
    tmp=$(jq --arg k "$key" --argjson i "$idx" '.last_quips[$k] = $i' "$STATE_FILE" 2>/dev/null || echo "")
    [ -n "$tmp" ] && echo "$tmp" > "$STATE_FILE"
  fi

  jq -r ".[\"$key\"][$idx]" "$QUIPS_FILE"
}

# Calculate fermentation level based on session duration and time of day.
# Returns: fresh|brined|fermented|extra_fermented
cmd_fermentation() {
  local session_start elapsed_min hour

  session_start=$(read_state "session_start")
  if [ -z "$session_start" ] || [ "$session_start" = "null" ]; then
    echo "fresh"
    return
  fi

  elapsed_min=$(( ($(now_epoch) - session_start) / 60 ))
  hour=$(current_hour)

  if [ "$elapsed_min" -ge 90 ] && [ "$hour" -lt 5 ]; then
    echo "extra_fermented"
  elif [ "$elapsed_min" -ge 90 ]; then
    echo "fermented"
  elif [ "$elapsed_min" -ge 30 ]; then
    echo "brined"
  else
    echo "fresh"
  fi
}

# Determine current mood emoji via priority logic (highest priority wins).
# Priority: idle > hungry > completion > flow > on_a_roll > late_night > default
cmd_mood() {
  local hunger last_prompt now_ts idle_sec hour

  now_ts=$(now_epoch)

  # 1. Idle check (no input for 15+ min)
  last_prompt=$(read_state "last_prompt_time")
  if [ -n "$last_prompt" ] && [ "$last_prompt" != "null" ] && [ "$last_prompt" -gt 0 ]; then
    idle_sec=$((now_ts - last_prompt))
    if [ "$idle_sec" -ge 900 ]; then
      echo "😴"
      return
    fi
  fi

  # 2. Hungry (hunger >= 40)
  hunger=$(read_state "hunger")
  hunger=${hunger:-0}
  if [ "$hunger" -ge 40 ]; then
    echo "🍜"
    return
  fi

  # 3. Big completion (flag set, less than 2 min ago)
  local completion_time
  completion_time=$(read_state "last_completion")
  if [ -n "$completion_time" ] && [ "$completion_time" != "null" ] && [ "$completion_time" -gt 0 ]; then
    if [ $((now_ts - completion_time)) -lt 120 ]; then
      echo "👑"
      return
    fi
  fi

  # 4. Deep flow (sustained rapid input for 10+ min)
  local flow_start
  flow_start=$(read_state "flow_start")
  if [ -n "$flow_start" ] && [ "$flow_start" != "null" ] && [ "$flow_start" -gt 0 ]; then
    if [ $((now_ts - flow_start)) -ge 600 ]; then
      echo "🪔"
      return
    fi
  fi

  # 5. On a roll (rapid inputs, short burst, tracked by rapid_count)
  local rapid_count
  rapid_count=$(read_state "rapid_count")
  rapid_count=${rapid_count:-0}
  if [ "$rapid_count" -ge 3 ]; then
    echo "🛸"
    return
  fi

  # 6. Late night (after midnight, before 5am)
  hour=$(current_hour)
  if [ "$hour" -lt 5 ]; then
    echo "🌌"
    return
  fi

  # 7. Default
  echo "🌶️"
}

# Apply stat decay. Hunger +10 and happiness -5 for each 30 min interval since last decay.
cmd_decay() {
  local last_decay now_ts elapsed intervals hunger happiness

  last_decay=$(read_state "last_decay_time")
  now_ts=$(now_epoch)

  if [ -z "$last_decay" ] || [ "$last_decay" = "null" ]; then
    update_field "last_decay_time" "$now_ts"
    return
  fi

  elapsed=$((now_ts - last_decay))
  intervals=$((elapsed / 1800))

  if [ "$intervals" -le 0 ]; then
    return
  fi

  hunger=$(read_state "hunger")
  happiness=$(read_state "happiness")
  hunger=${hunger:-0}
  happiness=${happiness:-80}

  hunger=$((hunger + intervals * 10))
  happiness=$((happiness - intervals * 5))

  # Clamp to 0-100
  [ "$hunger" -gt 100 ] && hunger=100
  [ "$hunger" -lt 0 ] && hunger=0
  [ "$happiness" -gt 100 ] && happiness=100
  [ "$happiness" -lt 0 ] && happiness=0

  local new_decay_time
  new_decay_time=$((last_decay + intervals * 1800))

  local tmp
  tmp=$(jq \
    --argjson h "$hunger" \
    --argjson hp "$happiness" \
    --argjson dt "$new_decay_time" \
    '.hunger = $h | .happiness = $hp | .last_decay_time = $dt' \
    "$STATE_FILE")
  echo "$tmp" > "$STATE_FILE"
}

# Render active display: ASCII Kimchi with quip, formatted for markdown output.
# Args: face, quip
render_active() {
  local face="${1:-( ˘▽˘)}" quip="${2:-}" mode="${3:-}"

  echo ""
  case "$mode" in
    pet)
      echo "  ${face}  <3"
      echo "   ~  ~"
      echo ""
      echo "  \"${quip}\""
      ;;
    feed)
      echo "  ${face}  nom nom  <3"
      echo "   ~  ~   🍙"
      echo ""
      echo "  \"${quip}\""
      ;;
    *)
      echo "  ${face}"
      echo "   ~  ~"
      echo ""
      echo "  \"${quip}\""
      ;;
  esac
  echo ""
}

# Standalone render command for testing
cmd_render() {
  local face="${1:-( ˘▽˘)}" quip="${2:-}"
  render_active "$face" "$quip"
}

# /pet - Boosts happiness by 20, shows reaction
cmd_pet() {
  local happiness now_ts
  now_ts=$(now_epoch)

  happiness=$(read_state "happiness")
  happiness=${happiness:-50}
  happiness=$((happiness + 20))
  [ "$happiness" -gt 100 ] && happiness=100

  local tmp
  tmp=$(jq \
    --argjson hp "$happiness" \
    --argjson pt "$now_ts" \
    '.happiness = $hp | .last_pet = $pt' \
    "$STATE_FILE")
  echo "$tmp" > "$STATE_FILE"

  local quip
  quip=$(cmd_quip any pet)
  render_active "(♡‿♡ )" "$quip" pet
}

# /feed - Feeds and pets in one gesture: hunger to 0, happiness +20
cmd_feed() {
  local happiness now_ts
  now_ts=$(now_epoch)

  happiness=$(read_state "happiness")
  happiness=${happiness:-50}
  happiness=$((happiness + 20))
  [ "$happiness" -gt 100 ] && happiness=100

  local tmp
  tmp=$(jq \
    --argjson hp "$happiness" \
    --argjson ft "$now_ts" \
    '.hunger = 0 | .happiness = $hp | .last_fed = $ft | .last_pet = $ft' \
    "$STATE_FILE")
  echo "$tmp" > "$STATE_FILE"

  local quip
  quip=$(cmd_quip any feed)
  render_active "(♡‿♡ )" "$quip" feed
}

# /buddy - Full status view
cmd_buddy() {
  local hunger happiness prompt_count session_start now_ts elapsed_min mood level

  hunger=$(read_state "hunger")
  happiness=$(read_state "happiness")
  prompt_count=$(read_state "prompt_count")
  session_start=$(read_state "session_start")
  now_ts=$(now_epoch)
  mood=$(cmd_mood)
  level=$(cmd_fermentation)

  hunger=${hunger:-0}
  happiness=${happiness:-80}
  prompt_count=${prompt_count:-0}
  session_start=${session_start:-$now_ts}

  elapsed_min=$(( (now_ts - session_start) / 60 ))

  # Quip matched to the mood: idle and hungry have their own pools,
  # everything else draws from the fermentation-level pool.
  local quip
  case "$mood" in
    "😴") quip=$(cmd_quip any idle) ;;
    "🍜") quip=$(cmd_quip any hungry) ;;
    *)    quip=$(cmd_quip "$level" general) ;;
  esac

  local face
  case "$mood" in
    "😴") face="( -_-)" ;;
    "🍜") face="( ˘~˘)" ;;
    "👑") face='\( ◕▽◕)/' ;;
    "🪔") face="( ˘▽˘)" ;;
    "🛸") face="( ◕▽◕)" ;;
    "🌌") face="( ¬‿¬)" ;;
    *)     face="( ˘▽˘)" ;;
  esac

  cat << ENDBUDDY
\`\`\`
              ╭ ${mood} ╮
 mood: $(printf '%-8s' "$mood")  ${face}  session: ${elapsed_min}m
 hunger: $(printf '%-5s' "$hunger")  ╰~~~~╯  prompts: ${prompt_count}
 happiness: $(printf '%-2s' "$happiness")  ~  ~
            vibe: ${level}
\`\`\`

  "${quip}"
ENDBUDDY
}

# /wrong - Log rendering feedback
cmd_wrong() {
  local note="${1:-no description}"
  local mood level cols rows
  local wrong_file="${KIMCHI_WRONG_FILE:-$WRONG_FILE}"

  mood=$(cmd_mood)
  level=$(cmd_fermentation)
  cols=$(tput cols 2>/dev/null || echo 80)
  rows=$(tput lines 2>/dev/null || echo 24)

  local session_start elapsed_min
  session_start=$(read_state "session_start")
  session_start=${session_start:-$(now_epoch)}
  elapsed_min=$(( ($(now_epoch) - session_start) / 60 ))

  local entry
  entry=$(jq -n \
    --arg ts "$(now_iso)" \
    --arg mood "$mood" \
    --arg level "$level" \
    --arg note "$note" \
    --argjson cols "$cols" \
    --argjson rows "$rows" \
    --argjson dur "$elapsed_min" \
    '{
      timestamp: $ts,
      mood: $mood,
      fermentation: $level,
      terminal_cols: $cols,
      terminal_rows: $rows,
      session_duration_min: $dur,
      user_note: $note
    }')

  if [ -f "$wrong_file" ]; then
    local tmp
    tmp=$(jq ". + [$entry]" "$wrong_file")
    echo "$tmp" > "$wrong_file"
  else
    echo "[$entry]" > "$wrong_file"
  fi

  echo "Logged. Thanks for the feedback."
}

# Classify the user's prompt text into an activity tag.
# Priority order (first match wins): builder_meta, builder, researcher, asker, actor, none.
classify_activity() {
  local text="$1"
  local lower
  lower=$(echo "$text" | tr '[:upper:]' '[:lower:]')

  # Skill/agent meta-builder
  if [[ "$lower" =~ (^|[^a-z])(skill|agent|subagent|hook|anthropic)([^a-z]|$) ]] \
     || [[ "$lower" == *"claude code"* ]] \
     || [[ "$lower" == *"claude/"* ]] \
     || [[ "$lower" == *"/claude"* ]]; then
    echo "builder_meta"; return
  fi

  # Builder
  if [[ "$lower" =~ (^|[^a-z])(build|create|implement|add|make|write|scaffold)([^a-z]|$) ]]; then
    echo "builder"; return
  fi

  # Researcher
  if [[ "$lower" =~ (^|[^a-z])(research|find|search|investigate|explore|compare)([^a-z]|$) ]] \
     || [[ "$lower" =~ look[[:space:]]+up ]]; then
    echo "researcher"; return
  fi

  # Asker (ends with ? or starts with question word)
  if [[ "$text" =~ \?[[:space:]]*$ ]]; then
    echo "asker"; return
  fi
  if [[ "$lower" =~ ^(who|what|where|when|why|how|can|could|should|does|is|are|do)([^a-z]|$) ]]; then
    echo "asker"; return
  fi

  # Action
  if [[ "$lower" =~ (^|[^a-z])(run|deploy|ship|test|check|fix)([^a-z]|$) ]]; then
    echo "actor"; return
  fi

  echo "none"
}

# Map activity tag to a face. Empty string if "none".
activity_face() {
  case "$1" in
    builder_meta) echo "(ง ˘▽˘)ง" ;;
    builder)      echo "( ˘▽˘)b" ;;
    researcher)   echo "( ˘ᴗ˘)?" ;;
    asker)        echo "( ◕‿◕)?" ;;
    actor)        echo "( ◕▽◕)" ;;
    *)            echo "" ;;
  esac
}

# Tick - called by UserPromptSubmit hook on every user message.
# Silent: tracks state only. Reactive faces surface in the statusline via pending_* fields.
# Reads event JSON from stdin (.prompt) for activity classification.
cmd_tick() {
  if [ ! -f "$STATE_FILE" ]; then
    cmd_init
  fi

  local now_ts
  now_ts=$(now_epoch)

  # Capture stdin (hook event JSON). Tolerate empty/non-JSON for manual invocation.
  local stdin_json prompt_text
  if [ ! -t 0 ]; then
    stdin_json=$(cat 2>/dev/null || echo "{}")
  else
    stdin_json="{}"
  fi
  [ -z "$stdin_json" ] && stdin_json="{}"
  prompt_text=$(echo "$stdin_json" | jq -r '.prompt // ""' 2>/dev/null || echo "")

  # Classify activity from prompt text
  local activity
  activity=$(classify_activity "$prompt_text")

  # --- Clear pending_* from previous tick (one-shot face overrides) ---
  local tmp_clear
  tmp_clear=$(jq '.pending_milestone = null | .pending_return = null | .pending_hydrate = false | .pending_quip = null' "$STATE_FILE")
  echo "$tmp_clear" > "$STATE_FILE"

  # --- Counters and sequence tracking ---
  local prompt_count last_prompt rapid_count lifetime_prompts prev_activity activity_streak
  prompt_count=$(read_state "prompt_count")
  prompt_count=${prompt_count:-0}
  prompt_count=$((prompt_count + 1))

  lifetime_prompts=$(read_state "lifetime_prompts")
  lifetime_prompts=${lifetime_prompts:-0}
  lifetime_prompts=$((lifetime_prompts + 1))

  prev_activity=$(read_state "current_activity")
  prev_activity=${prev_activity:-none}
  activity_streak=$(read_state "activity_streak")
  activity_streak=${activity_streak:-0}
  if [ "$activity" = "$prev_activity" ] && [ "$activity" != "none" ]; then
    activity_streak=$((activity_streak + 1))
  else
    activity_streak=1
  fi

  # Rapid input tracking (existing)
  last_prompt=$(read_state "last_prompt_time")
  last_prompt=${last_prompt:-0}
  rapid_count=$(read_state "rapid_count")
  rapid_count=${rapid_count:-0}
  if [ "$last_prompt" -gt 0 ] && [ $((now_ts - last_prompt)) -lt 120 ]; then
    rapid_count=$((rapid_count + 1))
  else
    rapid_count=0
  fi

  # Flow state (existing)
  local flow_start
  flow_start=$(read_state "flow_start")
  flow_start=${flow_start:-0}
  if [ "$rapid_count" -ge 1 ] && [ "$flow_start" -eq 0 ]; then
    flow_start=$now_ts
  elif [ "$rapid_count" -eq 0 ]; then
    flow_start=0
  fi

  # Persist core state in one jq call
  local tmp
  tmp=$(jq \
    --argjson pc "$prompt_count" \
    --argjson lp "$now_ts" \
    --argjson rc "$rapid_count" \
    --argjson fs "$flow_start" \
    --argjson lt "$lifetime_prompts" \
    --argjson act_streak "$activity_streak" \
    --arg ca "$activity" \
    '.prompt_count = $pc |
     .last_prompt_time = $lp |
     .rapid_count = $rc |
     .flow_start = $fs |
     .lifetime_prompts = $lt |
     .activity_streak = $act_streak |
     .current_activity = $ca' \
    "$STATE_FILE")
  echo "$tmp" > "$STATE_FILE"

  cmd_decay

  # --- Set pending_* face overrides for the statusline ---

  # 1. Milestone (1, 10, 50, 100) — one-shot, tracked in milestones_hit
  for ms in 1 10 50 100; do
    if [ "$lifetime_prompts" -eq "$ms" ]; then
      local already_hit
      already_hit=$(jq -r ".milestones_hit | index($ms) // \"no\"" "$STATE_FILE")
      if [ "$already_hit" = "no" ]; then
        local tmp2
        tmp2=$(jq --argjson ms "$ms" '.milestones_hit += [$ms] | .pending_milestone = ($ms | tostring)' "$STATE_FILE")
        echo "$tmp2" > "$STATE_FILE"
        ms_quip=$(cmd_quip any "milestone_$ms")
        update_field "pending_quip" "$(jq -n --arg q "$ms_quip" '$q')"
        break
      fi
    fi
  done

  # 2. Hydration nag (session ≥ 45 min, fires once per session)
  local session_start session_min hydration_warned
  session_start=$(read_state "session_start")
  session_start=${session_start:-$now_ts}
  session_min=$(( (now_ts - session_start) / 60 ))
  hydration_warned=$(read_state "hydration_warned")
  hydration_warned=${hydration_warned:-false}
  if [ "$session_min" -ge 45 ] && [ "$hydration_warned" = "false" ]; then
    update_field "hydration_warned" "true"
    update_field "pending_hydrate" "true"
    hy_quip=$(cmd_quip any hydrate)
    update_field "pending_quip" "$(jq -n --arg q "$hy_quip" '$q')"
  fi

  # Always silent — statusline handles all visual surfacing
  echo '{}'
}

# Greet - called by SessionStart hook. Silent: detects time gap since last prompt
# and sets pending_return for the statusline to surface as a face override.
cmd_greet() {
  # Capture last_prompt_time BEFORE cmd_init
  local prev_prompt_time
  prev_prompt_time=$(read_state "last_prompt_time")
  prev_prompt_time=${prev_prompt_time:-0}

  cmd_init

  local now_ts gap_sec gap_min return_bucket
  now_ts=$(now_epoch)

  if [ "$prev_prompt_time" -gt 0 ]; then
    gap_sec=$((now_ts - prev_prompt_time))
  else
    gap_sec=0
  fi
  gap_min=$((gap_sec / 60))

  # Pick return bucket
  if [ "$prev_prompt_time" -eq 0 ] || [ "$gap_min" -lt 15 ]; then
    return_bucket="none"
  elif [ "$gap_min" -lt 60 ]; then
    return_bucket="short"
  elif [ "$gap_min" -lt 240 ]; then
    return_bucket="medium"
  elif [ "$gap_min" -lt 720 ]; then
    return_bucket="long"
  else
    return_bucket="next_day"
  fi

  if [ "$return_bucket" != "none" ]; then
    update_field "pending_return" "\"$return_bucket\""
    ret_quip=$(cmd_quip any "return_$return_bucket")
    update_field "pending_quip" "$(jq -n --arg q "$ret_quip" '$q')"
  fi

  # Set last_prompt_time so we're not immediately idle
  update_field "last_prompt_time" "$now_ts"

  # Silent — statusline handles all visual surfacing
  echo '{}'
}

# --- Main dispatch ---
cmd="${1:-help}"
case "$cmd" in
  init)          cmd_init ;;
  quip)          cmd_quip "${2:-fresh}" "${3:-general}" ;;
  fermentation)  cmd_fermentation ;;
  mood)          cmd_mood ;;
  decay)         cmd_decay ;;
  pet)           cmd_pet ;;
  feed)          cmd_feed ;;
  buddy)         cmd_buddy ;;
  render)        cmd_render "${2:-( ˘▽˘)}" "${3:-}" ;;
  wrong)         cmd_wrong "${2:-}" ;;
  tick)          cmd_tick ;;
  greet)         cmd_greet ;;
  *)             echo "Unknown command: $cmd" >&2; exit 1 ;;
esac
