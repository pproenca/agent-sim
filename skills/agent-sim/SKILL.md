---
name: agent-sim
description: Explore and test iOS Simulator apps with a 2-command loop.
---

# agent-sim

Drive an iOS Simulator app. The loop is: observe, act, repeat.

## Core Loop

```
agent-sim explore -i    # See interactive elements with @eN refs
agent-sim tap @e3       # Tap element @e3. Returns "Done".
agent-sim explore -i    # See what changed
```

## Commands

| Command | What it does |
|---------|-------------|
| `explore -i` | List interactive elements with `@eN` refs |
| `explore -i --screenshot <path>` | Same + capture screenshot |
| `tap @eN` | Tap element by ref -> "Done" |
| `tap --label "X"` | Tap by label (fallback) |
| `swipe up\|down\|left\|right` | Scroll -> "Done" |
| `type "text"` | Type into focused field -> "Done" |
| `screenshot [path]` | Capture screen |
| `ui assert visible "X"` | Verify element exists |
| `ui wait` | Wait until screen is ready |
| `sim boot` | Boot simulator |
| `sim list` | List simulators |
| `config set -S "iPhone 16"` | Save project settings |
| `stop <bundleId>` | Stop running app |
| `launch <bundleId>` | Launch app |
| `doctor` | Health check |

## Rules

- Always `explore -i` before acting. Refs refresh each time.
- Use `@eN` refs, not coordinates. Coordinates are a last resort.
- Skip destructive elements (Delete, Sign Out) unless told otherwise.
- If 0 interactive elements: a system dialog may be blocking. Use `screenshot` + `tap <x> <y>`.
- Each `explore -i` output shows screen name, element count, and fingerprint for navigation tracking.
