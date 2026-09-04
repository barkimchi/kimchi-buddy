---
description: Check on Kimchi - status, help, and feedback
argument-hint: [help | wrong <note>]
allowed-tools: [Bash]
---

Parse `$ARGUMENTS` and follow the first matching case:

1. No arguments: run this command and display the output exactly as-is (it contains a pre-formatted status view):

```bash
bash ~/.claude/kimchi/kimchi.sh buddy
```

2. `help`: display this exactly:

```
+----------------------------------------------+
|           KIMCHI BUDDY                        |
+----------------------------------------------+
|                                               |
|  /kimchi              Check on Kimchi         |
|  /kimchi-feed         Feed and pet Kimchi     |
|  /kimchi-goal         Goals and timers        |
|                       /kimchi-goal 50 prompts |
|                       /kimchi-goal 90m        |
|                       /kimchi-goal standup    |
|                       in 15m                  |
|                       /kimchi-goal clear      |
|  /kimchi-settings     Colors, widgets,        |
|                       records, updates        |
|                                               |
|  /kimchi wrong <note> Report a render issue   |
|                                               |
+----------------------------------------------+
```

3. `wrong <note>`: run this command with the note text (everything after "wrong"):

```bash
bash ~/.claude/kimchi/kimchi.sh wrong "<note>"
```

Then display: "Got it, logged the issue. I'll try to do better."

Do not add any extra commentary beyond what the matched case specifies.
