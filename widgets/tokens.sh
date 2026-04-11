# Token Usage Widget
# Displays exact token count used in the current session.
# Reads context window data from status line stdin JSON.

# Known context window sizes by model
_tokens_context_size() {
  local model
  model=$(echo "$W_INPUT" | jq -r '.model.display_name // .model.id // ""' 2>/dev/null || echo "")
  # Default context sizes based on model family
  case "$model" in
    *Opus*4.6*|*opus*4.6*)     echo 1000000 ;;
    *Sonnet*4.6*|*sonnet*4.6*) echo 200000 ;;
    *Haiku*4.5*|*haiku*4.5*)   echo 200000 ;;
    *Opus*4*|*opus*4*)         echo 200000 ;;
    *Sonnet*4*|*sonnet*4*)     echo 200000 ;;
    *)                          echo 200000 ;;  # safe default
  esac
}

# Format token count as human-readable
_tokens_format() {
  local tokens="$1"
  if [ "$tokens" -ge 1000000 ]; then
    local m=$(( tokens / 1000000 ))
    local k=$(( (tokens % 1000000) / 100000 ))
    printf '%s.%sM' "$m" "$k"
  elif [ "$tokens" -ge 1000 ]; then
    local k=$(( tokens / 1000 ))
    local h=$(( (tokens % 1000) / 100 ))
    if [ "$k" -ge 100 ]; then
      printf '%sK' "$k"
    else
      printf '%s.%sK' "$k" "$h"
    fi
  else
    printf '%s' "$tokens"
  fi
}

widget_tokens_render() {
  # Need W_INPUT (status line JSON) for context window data
  if [ -z "$W_INPUT" ]; then
    return 0
  fi

  local remaining_pct
  remaining_pct=$(echo "$W_INPUT" | jq -r '.context_window.remaining_percentage // empty' 2>/dev/null || echo "")

  if [ -z "$remaining_pct" ]; then
    return 0
  fi

  local context_size
  context_size=$(_tokens_context_size)

  # Compute used tokens: (100 - remaining%) * total / 100
  # Use awk for floating point math since bash only does integers
  local used_tokens
  used_tokens=$(awk -v pct="$remaining_pct" -v total="$context_size" \
    'BEGIN { printf "%.0f", (100 - pct) * total / 100 }')

  # Persist current token estimate so session-end can accumulate it
  w_update_state --argjson t "$used_tokens" '.session_tokens_used = $t' 2>/dev/null || true

  local formatted
  formatted=$(_tokens_format "$used_tokens")

  printf '%s tok' "$formatted"
}
