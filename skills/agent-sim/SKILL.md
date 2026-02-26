---
name: agent-sim
description: Explore and test iOS apps in Simulator using the AgentSim CLI with guided next-step commands and journaling.
---

# agent-sim

Use this skill when an agent needs to interact with an iOS Simulator app through `agent-sim`.

## When to use

- You need guided UI exploration via `agent-sim next`.
- You need reproducible action logs with `agent-sim journal`.
- You need simulator interaction without taking over mouse/keyboard.

## Instructions

1. Build the app first using Xcode or `xcodebuild`. Do not use AgentSim for build steps.
2. Start by running `agent-sim next --journal <path>` and copy the returned `action.command`.
3. After every action, run `agent-sim wait --timeout 5`, `agent-sim fingerprint --hash-only`, and `agent-sim explore --annotate --pretty`.
4. Execute taps from copied commands (`tap --box N` from `explore --annotate` or `action.command` from `next`), not from generated coordinates.
5. Log each action immediately with `agent-sim journal log ... --auto-after`.
6. If the app crashes or gets stuck, call `agent-sim next --journal <path>` again and follow its recovery action.

## Guardrails

- Use only `agent-sim` for simulator UI interactions.
- Prefer `tap --box N` over labels or raw coordinates.
- Avoid destructive actions (delete/sign out/remove) during exploratory sweeps.
- Do not type into text fields unless the task explicitly requires it.
