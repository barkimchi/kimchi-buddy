---
description: Set or check session goals and countdown timers
argument-hint: [50 prompts | 90m | <label> in <time> | clear [label]]
allowed-tools: [Bash]
---

Parse `$ARGUMENTS` and follow the first matching case:

1. No arguments: show the current goal and all countdowns:

```bash
bash ~/.claude/kimchi/widgets.sh goal-status
```

2. `clear` alone: clear the current session goal:

```bash
bash ~/.claude/kimchi/widgets.sh goal-clear
```

3. `clear <label>`: remove the countdown with that label:

```bash
bash ~/.claude/kimchi/widgets.sh countdown-remove <label>
```

4. `clear all`: clear the goal and every countdown:

```bash
bash ~/.claude/kimchi/widgets.sh goal-clear
bash ~/.claude/kimchi/widgets.sh countdown-remove-all
```

5. A number followed by "prompt" or "prompts" (e.g. "50 prompts"): set a prompt goal:

```bash
bash ~/.claude/kimchi/widgets.sh goal-set prompts <number>
```

6. A bare duration (e.g. "90m", "2h"): set a duration goal in minutes ("Xm" = X, "Xh" = X * 60):

```bash
bash ~/.claude/kimchi/widgets.sh goal-set duration <minutes>
```

7. Anything else with a label and a time (e.g. "standup in 15m", "deploy 2h"): set a countdown. The label is the first word; convert the time to seconds ("Xm" = X * 60, "Xh" = X * 3600):

```bash
bash ~/.claude/kimchi/widgets.sh countdown-set <label> <seconds>
```

Display the output. Do not add any extra commentary.
