# AgentSim — Agent Instructions

Instructions for AI agents (Claude Code, Cursor, etc.) using AgentSim to explore and test iOS apps.

## Design Principle — Copy, Don't Generate

AgentSim's output is designed so the **next command you need is already in the output**.
LLMs are reliable at copying tokens they just read, unreliable at constructing commands
from memory. Every AgentSim command follows this principle:

- `explore -i` returns `@eN` refs — copy the ref from output
- `explore --annotate` returns `tap --box N` — copy the box number from output
- Error messages include what's available, so recovery is also copy-based

**Always prefer the highest-fidelity reference:**

| Best (copy) | Acceptable | Avoid (generate from memory) |
|---|---|---|
| `tap @e3` (from explore -i) | `tap --label "Sign In"` (from explore output) | `tap 196 400` (coordinates from memory) |
| `tap --box 3` (from explore --annotate) | Copy label from `explore` JSON | Construct commands from context |

## Tool Boundary — READ THIS FIRST

**AgentSim is the ONLY tool you use for simulator interaction.** Everything you need is a single CLI command away.

| Need | AgentSim command | NEVER use |
|------|-----------------|-----------|
| Boot a simulator | `agent-sim sim boot "iPhone 16"` | ~~open -a Simulator~~ ~~xcrun simctl boot~~ |
| Install an app | `agent-sim sim install path/to/App.app` | ~~xcrun simctl install~~ |
| Find bundle IDs | `agent-sim sim apps --pretty` | ~~manual Info.plist parsing~~ |
| Wait for readiness | `agent-sim ui wait` | ~~sleep 2~~ |
| See what's on screen | `agent-sim explore` or `agent-sim explore --raw` | ~~XcodeBuildMCP snapshot_ui~~ |
| See + annotated screenshot | `agent-sim explore --annotate` | ~~XcodeBuildMCP screenshot~~ |
| Tap an element | `agent-sim tap @eN` or `agent-sim tap --label "X"` | ~~XcodeBuildMCP tap~~ ~~xcrun simctl~~ |
| Swipe/scroll | `agent-sim swipe up` | ~~XcodeBuildMCP gesture/swipe~~ |
| Type text | `agent-sim type "hello"` | ~~XcodeBuildMCP type_text~~ |
| Take plain screenshot | `agent-sim screenshot` or `agent-sim explore --screenshot path` | ~~xcrun simctl io~~ |
| Launch app | `agent-sim launch <bundleId>` | ~~xcrun simctl launch~~ |
| Stop app | `agent-sim stop <bundleId>` | ~~xcrun simctl terminate~~ |
| Check health | `agent-sim doctor` | ~~XcodeBuildMCP list_sims~~ |
| Detect screen changes | `agent-sim explore --fingerprint` | ~~custom hashing~~ |
| Verify state | `agent-sim ui assert visible "X"` | ~~manual grep/parse~~ |

**Why this matters:**
- AgentSim outputs coordinates in device-point space. These coordinates work directly with `agent-sim tap`. If you mix tools (e.g., read coordinates from XcodeBuildMCP, tap with agent-sim), they use different coordinate spaces and taps will miss.
- AgentSim's explore-based workflow tracks what you've seen. If you use other tools for actions, you lose that context.

**The only exception:** `XcodeBuildMCP build_sim` or `xcodebuild` for **building** the app. AgentSim does not build — it explores what's already built and running.

## TL;DR

1. `agent-sim explore -i` — always start here. See what's on screen with `@eN` refs.
2. `agent-sim tap @eN` — tap the element you want.
3. `agent-sim explore -i` — see what changed.
4. Repeat until you've covered all reachable screens.

## Annotated Screenshots (explore --annotate)

When you need to see the screen visually AND act on what you see:

```bash
agent-sim explore --annotate --pretty
```

This does three things in one command:
1. Captures a screenshot with numbered red bounding boxes on every interactive element
2. Saves it to a default path (printed in output as `Annotated: <path>`)
3. Prints each element with its exact tap command

**Example output:**
```
Screen: Onboarding
Fingerprint: 20b971e1890472d3
Elements: 12 total, 3 interactive
Annotated: .agent-sim/journals/last-explore.png

Actions (3):
  #1 [AXButton] "Sign In" id="login.button"  →  tap --box 1
  #2 [AXButton] "Create Account"  →  tap --box 2
  #3 [AXButton] "Skip"  →  tap --box 3
```

**To act on what you see:** copy the tap command from the output.

```bash
# You see #1 in the screenshot, the output says:  →  tap --box 1
agent-sim tap --box 1
```

**Box numbers are stable until the next `explore --annotate` call.** Each annotated
explore overwrites the mapping. If you need to re-read the screen, run `explore --annotate`
again — the numbers will update to match the new screen state.

**When to use `--annotate` vs plain `explore`:**
- Use `--annotate` when you need visual context (layout, images, colors) alongside element data
- Use plain `explore` during fast exploration loops where speed matters
- Use `--screenshot <path>` when you need a clean, unannotated screenshot (design review, visual QA)

## The Loop

AgentSim uses a simple **observe-act-repeat** loop:

```
agent-sim explore -i          # See interactive elements with @eN refs
  ↓
Pick an element to tap
  ↓
agent-sim tap @eN             # Tap it
  ↓
agent-sim explore -i          # See what changed
  ↓
Repeat until all reachable screens are covered
```

Each `explore -i` output shows:
- **Screen name** and **fingerprint** — for tracking navigation
- **Interactive elements** with `@eN` refs — copy these for `tap`
- **Element count** — to know when a screen is fully explored

## Cold Start (First Run)

```bash
# 1. Boot a simulator (waits until fully usable — no sleep needed)
agent-sim sim boot "iPhone 16"

# 2. Install the app (returns the bundle ID)
agent-sim sim install path/to/MyApp.app

# 3. Launch the app
agent-sim launch com.example.myapp

# 4. Wait for the screen to be ready
agent-sim ui wait

# 5. Start exploring
agent-sim explore -i

# Now you're in the loop.
```

## The Observe-Act Cycle

Every iteration follows this pattern:

### 1. Observe the screen
```bash
agent-sim explore -i
```

### 2. Tap an element
```bash
# Copy the @eN ref from the explore output
agent-sim tap @e3
```

### 3. Observe what changed
```bash
agent-sim explore -i
```

Compare fingerprints between observations:
- Different fingerprint → screen changed (navigated)
- Same fingerprint → stayed on same screen

## Issue Detection

Flag an issue when you observe:

| Signal | What it means |
|--------|---------------|
| Fingerprint changed but `explore` shows unexpected screen | **Wrong navigation** — tapping "Back" went to Home instead of parent |
| `ui assert visible "label"` fails | **Missing element** — expected content is absent |
| `explore` returns 0 elements or shows SpringBoard | **Crash** — app terminated |
| Fingerprint unchanged after tapping interactive element | **Stuck** — element didn't respond |
| Interactive element has no label or identifier | **Accessibility gap** — missing a11y metadata |

## Verification

Use `ui assert` to verify expected state at any point:

```bash
# Check element is visible
agent-sim ui assert visible "Welcome"

# Check element is hidden
agent-sim ui assert hidden "Error"

# Check text content
agent-sim ui assert text "Welcome to MyApp"

# Check element is enabled
agent-sim ui assert enabled "Submit"
```

Assert returns exit code 0 on pass, 1 on fail. JSON output includes all assertion results.

## Commands Reference

### Simulator management
| Command | Use when |
|---------|----------|
| `sim boot [name]` | Need to boot a simulator. Waits until usable. |
| `sim list` | Need to see available simulators. |
| `sim install <path>` | Need to install a .app or .ipa. Returns bundle ID. |
| `sim apps [--pretty]` | Need to find installed bundle IDs. |
| `sim shutdown` | Need to shut down the booted simulator. |

### Observation (read-only)
| Command | Use when | Output contains next command? |
|---------|----------|------|
| `explore -i` | **Start here.** Interactive elements with `@eN` refs. | Yes — `tap @eN` per element |
| `explore --annotate [--pretty]` | Need screen analysis + annotated screenshot + tap commands | Yes — `tap --box N` per element |
| `explore [--pretty]` | Need screen analysis without screenshot overhead | No — use labels or coordinates |
| `explore --screenshot <path>` | Need clean unannotated screenshot (design review) | No |
| `explore --raw` | Need raw accessibility tree | No |
| `explore --fingerprint` | Need screen identity for transition detection | No |
| `explore --diff` | Need to see what changed since last explore | No |
| `screenshot [path]` | Need standalone screenshot | No |
| `doctor` | Need simulator/accessibility health check | No |

### Action (modifies state)
| Command | Use when |
|---------|----------|
| `tap @eN` | **Preferred.** Tap element by ref from last `explore -i`. |
| `tap --box N` | Tap element by box number from last `explore --annotate`. |
| `tap --label "text"` | Tap by accessibility label (when ref unavailable). |
| `tap --id "identifier"` | Tap by accessibility identifier. |
| `tap <x> <y>` | Tap by coordinates (last resort — fragile). |
| `swipe <direction>` | Swiping (up/down/left/right). |
| `type "text"` | Typing into a focused text field. |
| `launch <bundleId>` | Launching the app. |
| `stop <bundleId>` | Stopping the app. |

### Verification
| Command | Use when |
|---------|----------|
| `ui assert visible "label"` | Checking element exists |
| `ui assert hidden "label"` | Checking element is absent |
| `ui assert text "content"` | Checking text content |
| `ui assert enabled "label"` | Checking element is enabled |
| `ui wait` | Waiting until the screen is ready |
| `ui find "query"` | Finding elements matching a query |

### Configuration
| Command | Use when |
|---------|----------|
| `config set -S "iPhone 16"` | Saving project settings (simulator name) |
| `config show` | Viewing current configuration |
| `project context` | Viewing project context |

## Guardrails

These apply to every sweep. Violating them causes incorrect results.

1. **Copy refs from output** — do not construct commands from memory. Use `@eN` refs from `explore -i`, or `tap --box N` from `explore --annotate`.
2. **Always `explore -i` before acting** — refs refresh each time. Don't reuse stale refs.
3. **Skip destructive elements** — Delete, Sign Out, Remove, etc. These kill the session.
4. **Do not type into text fields** — focus on tap interactions during exploration.
5. **Wait after tapping** — use `agent-sim ui wait` before observing. Never use `sleep`.
6. **Dismiss modals before continuing** — sheets, alerts, and popovers must be closed before returning to parent screen traversal.
7. **If the app crashes, recover first** — screenshot, relaunch, verify the screen, then continue.
8. **Scroll before declaring a screen exhausted** — `agent-sim swipe up` to check for off-screen content.
9. **Do not retry crashed actions** — if an action caused a crash, skip it and move on.

## Claude Code Integration

AgentSim connects to Claude Code through the **Bash tool** — no MCP server needed.

```
Claude Code → Bash("agent-sim explore --annotate --pretty") → AgentSim CLI → stdout → Claude Code
```

This is the intended integration path. Do NOT use XcodeBuildMCP MCP tools for simulator
UI interaction when AgentSim is available. XcodeBuildMCP is for build/test/debug only.

**How to call from Claude Code:**
```bash
# All agent-sim commands run via Bash tool
agent-sim doctor                          # Health check
agent-sim explore -i                      # See interactive elements with @eN refs
agent-sim tap @e3                         # Tap element @e3
agent-sim explore --annotate --pretty     # Observe screen + get tap commands
agent-sim tap --box 1                     # Act on element #1 from annotated explore
agent-sim explore --fingerprint           # Detect transition
```

The binary lives at `tools/AgentSim/.build/debug/AgentSim`. If it's not built yet,
build it first with `cd tools/AgentSim && swift build`.

## Output Format

All commands output JSON by default. Use `--pretty` for human-readable output.

**Key principle:** When `--pretty` output includes actionable elements, it also includes
the exact command to act on them. Copy the command — do not construct your own.

JSON contracts are stable. Field names will not change between versions.
