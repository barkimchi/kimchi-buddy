---
description: Set a session goal to track progress
argument-hint: [target like "50 prompts", "2h", "90m"]
allowed-tools: [Bash]
---

If no arguments are provided, run this command and display the output:

```bash
bash ~/.claude/kimchi/widgets.sh render
```

Show only the Goal widget portion of the output.

If the argument is "clear", run:

```bash
bash ~/.claude/kimchi/widgets.sh goal-clear
```

Otherwise, parse the goal:
- If it contains "prompt" or "prompts": type is "prompts", target is the number (e.g., "50 prompts" -> type=prompts, target=50)
- If it contains "h" (hours): type is "duration", convert to minutes (e.g., "2h" -> type=duration, target=120)
- If it contains "m" (minutes): type is "duration", target is the number (e.g., "90m" -> type=duration, target=90)

Then run:

```bash
bash ~/.claude/kimchi/widgets.sh goal-set <type> <target>
```

Display the output. Do not add extra commentary.
