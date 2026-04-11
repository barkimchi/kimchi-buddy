---
description: Set or list countdown timers
argument-hint: [label] [time like 15m, 2h]
allowed-tools: [Bash]
---

If no arguments are provided, run this command and display the output:

```bash
bash ~/.claude/kimchi/widgets.sh countdown-list
```

If arguments are provided, parse them:
- First word is the label (e.g., "standup", "deploy", "break")
- Second word is the time (e.g., "15m", "2h", "30m")
- Convert time to seconds: "Xm" = X * 60, "Xh" = X * 3600

Then run:

```bash
bash ~/.claude/kimchi/widgets.sh countdown-set <label> <seconds>
```

To remove a countdown, if the user says "remove" or "clear" followed by a label:

```bash
bash ~/.claude/kimchi/widgets.sh countdown-remove <label>
```

Display the output. Do not add extra commentary.
