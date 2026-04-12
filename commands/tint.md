---
description: Set status line tint (named color or hex like #e8853b)
argument-hint: <name | #hex>
allowed-tools: [Bash]
---

Parse `$ARGUMENTS` as a color and write it to `~/.claude/kimchi/config.json`.

Rules:

1. If no argument, show the current tint:
   ```bash
   jq -r '.color // "orange"' ~/.claude/kimchi/config.json 2>/dev/null || echo "orange"
   ```
   Also print this list so the user knows their options:
   ```
   Named: orange blue green red purple pink yellow cyan white
   BarOS: ember maroon emerald gold cobalt violet
   Hex:   #rrggbb (e.g. #e8853b)
   ```

2. If argument is `list`, print the same options list above.

3. Otherwise, normalize the argument:
   - Lowercase it.
   - If it matches one of the named colors (orange, blue, green, red, purple, pink, yellow, cyan, white, ember, maroon, emerald, gold, cobalt, violet) — use as-is.
   - If it matches `^#?[0-9a-f]{6}$` — prepend `#` if missing.
   - Otherwise, print `Invalid color: <arg>` and stop.

4. Write the normalized value to the config using jq (do not shell out to `widgets.sh` — write directly so this keeps working if Kimchi Buddy self-updates):

   ```bash
   CONFIG=~/.claude/kimchi/config.json
   mkdir -p ~/.claude/kimchi
   [ -f "$CONFIG" ] || echo '{"show_cwd":true,"show_model":true,"show_context":true,"color":"orange"}' > "$CONFIG"
   tmp=$(jq --arg v "<normalized>" '.color = $v' "$CONFIG") && echo "$tmp" > "$CONFIG"
   echo "Tint set to <normalized>."
   ```

5. Do not add extra commentary beyond the confirmation line.
