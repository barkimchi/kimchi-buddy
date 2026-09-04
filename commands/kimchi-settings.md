---
description: Kimchi settings - colors, widgets, records, updates
argument-hint: [color <name|#hex> | show|hide <widget> | records | update]
allowed-tools: [Bash]
---

Parse `$ARGUMENTS` and follow the first matching case:

1. No arguments: show current settings:

```bash
bash ~/.claude/kimchi/widgets.sh config-show
```

2. `color <value>` or `tint <value>`: set the status line tint. Normalize the value: lowercase; named colors pass through; 6 hex digits with or without a leading # become #rrggbb. Named colors: orange, blue, green, red, purple, pink, yellow, cyan, white, ember, maroon, emerald, gold, cobalt, violet. If the value matches neither, print "Invalid color: <value>" and stop. Otherwise:

```bash
bash ~/.claude/kimchi/widgets.sh config-set color <normalized>
```

3. `color` or `tint` alone: print the current color and the options list:

```bash
jq -r '.color // "orange"' ~/.claude/kimchi/config.json 2>/dev/null || echo "orange"
```

```
Named: orange blue green red purple pink yellow cyan white
BarOS: ember maroon emerald gold cobalt violet
Hex:   #rrggbb (e.g. #e8853b)
```

4. `show <widget>` or `hide <widget>`: toggle a status line widget. Widget names: spice, streak, context, tokens, session, countdown, goal. "mood" is an alias for "spice". Run:

```bash
bash ~/.claude/kimchi/widgets.sh widget-enable <widget>
```

or

```bash
bash ~/.claude/kimchi/widgets.sh widget-disable <widget>
```

5. `show <element>` or `hide <element>` for cwd, model, or context: these are config flags, not widgets:

```bash
bash ~/.claude/kimchi/widgets.sh config-set show_cwd true|false
bash ~/.claude/kimchi/widgets.sh config-set show_model true|false
bash ~/.claude/kimchi/widgets.sh config-set show_context true|false
```

6. `records` or `highscore` or `highscores`: show the high score board:

```bash
bash ~/.claude/kimchi/widgets.sh records
```

7. `update`: update Kimchi Buddy from GitHub:

```bash
bash ~/.claude/kimchi/widgets.sh self-update
```

Display the output. Do not add any extra commentary.
