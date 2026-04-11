---
description: View or change Kimchi Buddy display settings
argument-hint: [setting value]
allowed-tools: [Bash]
---

If no arguments provided, show current settings:

```bash
bash ~/.claude/kimchi/widgets.sh config-show
```

If arguments provided, parse them:
- "color blue" -> key=color, value=blue
- "cwd off" or "cwd false" or "hide cwd" -> key=show_cwd, value=false
- "cwd on" or "cwd true" or "show cwd" -> key=show_cwd, value=true
- "model off/false/hide" -> key=show_model, value=false
- "model on/true/show" -> key=show_model, value=true
- "context off/false/hide" -> key=show_context, value=false
- "context on/true/show" -> key=show_context, value=true

Then run:

```bash
bash ~/.claude/kimchi/widgets.sh config-set <key> <value>
```

Display the output. Do not add extra commentary.
