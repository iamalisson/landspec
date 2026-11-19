---
name: help
description: "Explain landspec from its docs: commands, the feature and task loop, levels, configuration, security, and why things work the way they do. Use for /landspec:help or when the user asks how landspec works."
argument-hint: "[question]"
---

# landspec help

The docs are the source of truth. Read them, don't answer from memory, and read only what the
question needs:
- the commands, the loop, levels: `${CLAUDE_PLUGIN_ROOT}/README.md`;
- what runs automatically, configuration, update, uninstall, Claude Code tools:
  `${CLAUDE_PLUGIN_ROOT}/docs/reference.md`;
- why things work the way they do: `${CLAUDE_PLUGIN_ROOT}/docs/design.md`, and a worked feature
  in `${CLAUDE_PLUGIN_ROOT}/examples/README.md`;
- security: `${CLAUDE_PLUGIN_ROOT}/docs/security.md`;
- starting a project, architecture, "is this a good idea?": `${CLAUDE_PLUGIN_ROOT}/docs/GUIDELINES.md`
  and `${CLAUDE_PLUGIN_ROOT}/docs/GUARDRAILS.md`;
- "what's the current way to do X?": the matching entry in `${CLAUDE_PLUGIN_ROOT}/docs/references.yaml`.

1. **No argument**: show a short overview.
   - The loop: what you run once per feature. `/speckit-specify` makes the feature's one branch;
     `/landspec:implement` builds its tasks in parallel, each in its own copy and reviewed alone by
     Opus, lands each on the feature branch, and keeps one draft PR (`pr.sh feature`), marked ready
     after the end check. No GitHub issues; `/landspec:next` shows the progress.
   - The commands in one table: `/landspec:new`, `init`, `adopt`, `level`, `next`, `implement`,
     `security`, `aws`, `report`, `remove`, `help`, and the spec-kit commands they hook into.
   - The levels in one line each.
   - The config keys in `.specify/extensions/landspec/landspec-config.yml`.
   - If the current directory is a landspec project (`.specify/extensions/landspec/` exists), add one line
     about where it stands: its level, and "run `/landspec:next` to see progress".
2. **With a question**: answer it directly, in a few sentences, from the docs above. Quote the
   command to run when there is one. If the docs don't cover it, say so instead of guessing.
3. End with: "Worked example: `examples/` in the landspec repo (one feature, from spec to
   its merged PR)."
