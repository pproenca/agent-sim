# AgentSim — Agent Instructions

Instructions for AI agents (Claude Code, Cursor, etc.) using AgentSim to explore and test iOS apps.

## Design Principle — Copy, Don't Generate

AgentSim's output is designed so the **next command you need is already in the output**.
LLMs are reliable at copying tokens they just read, unreliable at constructing commands
from memory. Every AgentSim command follows this principle:

- `next` returns `action.command` — the exact CLI command to run
- `explore --annotate` returns `tap --box N` — copy the box number from output
- Error messages include what's available, so recovery is also copy-based

**Always prefer the highest-fidelity reference:**

| Best (copy) | Acceptable | Avoid (generate from memory) |
|---|---|---|
| `tap --box 3` (from explore --annotate) | `tap --label "Sign In"` (from explore output) | `tap 196 400` (coordinates from memory) |
| Copy `action.command` from `next` | Copy label from `explore` JSON | Construct commands from context |

## Tool Boundary — READ THIS FIRST

**AgentSim is the ONLY tool you use for simulator interaction.** Everything you need is a single CLI command away.

| Need | AgentSim command | NEVER use |
|------|-----------------|-----------|
| See what's on screen | `agent-sim explore` or `agent-sim describe` | ~~XcodeBuildMCP snapshot_ui~~ |
| See + annotated screenshot | `agent-sim explore --annotate` | ~~XcodeBuildMCP screenshot~~ |
| Tap an element | `agent-sim tap --box N` or `agent-sim tap --label "X"` | ~~XcodeBuildMCP tap~~ ~~xcrun simctl~~ |
| Swipe/scroll | `agent-sim swipe up` | ~~XcodeBuildMCP gesture/swipe~~ |
| Type text | `agent-sim type "hello"` | ~~XcodeBuildMCP type_text~~ |
| Take plain screenshot | `agent-sim screenshot` or `agent-sim explore --screenshot path` | ~~xcrun simctl io~~ |
| Launch/terminate app | `agent-sim launch <bundleId>` | ~~xcrun simctl launch~~ |
| Check health | `agent-sim status` | ~~XcodeBuildMCP list_sims~~ |
| Debug network errors | `agent-sim network --errors --pretty` | ~~Charles Proxy~~ ~~manual log parsing~~ |
| Detect screen changes | `agent-sim fingerprint` | ~~custom hashing~~ |
| Verify state | `agent-sim assert --contains "X"` | ~~manual grep/parse~~ |

**Why this matters:**
- AgentSim outputs coordinates in device-point space. These coordinates work directly with `agent-sim tap`. If you mix tools (e.g., read coordinates from XcodeBuildMCP, tap with agent-sim), they use different coordinate spaces and taps will miss.
- AgentSim's `next` command tracks exploration state. If you use other tools for actions, the state machine loses track and gives wrong instructions.
- AgentSim journals every action for reproducibility. Side-channel actions via xcrun/MCP create gaps in the journal.

**The only exception:** `XcodeBuildMCP build_sim` or `xcodebuild` for **building** the app. AgentSim does not build — it explores what's already built and running.

## TL;DR

1. `agent-sim next` — always start here. It tells you exactly what to do.
2. Follow the `afterAction` steps in order.
3. Call `agent-sim next --journal <path>` again after each action.
4. Repeat until `phase: "complete"`.

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

AgentSim uses a **typed state machine**. You never decide what to do — you ask `next` and it tells you.

```
agent-sim next --journal <path>
  ↓
Parse JSON response
  ↓
Branch on `phase`:
  "not_started"     → Run the action.command (journal init), then afterAction steps
  "new_screen"      → Run the action.command (tap), then afterAction steps
  "exploring"       → Run the action.command (tap), then afterAction steps
  "screen_exhausted"→ Run the action.command (back/swipe), then afterAction steps
  "crashed"         → Run the action.command (recover), then afterAction steps
  "complete"        → Stop. Run journal summary.
```

Every response includes:
- **`phase`** — typed state, branch on this
- **`instruction`** — human-readable explanation
- **`action.command`** — exact CLI command to run (copy-paste it)
- **`afterAction`** — ordered steps to run after the action (copy-paste each)
- **`guardrails`** — rules to follow (read these)
- **`progress`** — screens visited, actions taken, issues found

## Cold Start (First Run)

```bash
# 1. Ask what to do
agent-sim next

# Response: phase="not_started", action.command="agent-sim journal init ..."
# 2. Copy-paste the command and afterAction steps:
agent-sim journal init --path build/agent-sim/sweep-journal.md --simulator "iPhone 16" --scope "Full app exploration"
agent-sim launch com.maddie.appnative
sleep 2
agent-sim explore --annotate --pretty
agent-sim next --journal build/agent-sim/sweep-journal.md

# Now you're in the loop.
```

## The Observe-Act-Journal Cycle

Every iteration follows this pattern:

### 1. Get instruction
```bash
agent-sim next --journal <path>
```

### 2. Execute the action
```bash
# Copy the command from action.command — do not construct your own
agent-sim tap --box 1
```

### 3. Detect transition
```bash
sleep 1
agent-sim fingerprint --hash-only
```
Compare with `currentScreen.fingerprint` from the `next` response.
- Different hash → screen changed (navigated)
- Same hash → stayed on same screen

### 4. Observe new state
```bash
agent-sim explore --annotate --pretty
```

### 5. Journal the action
```bash
agent-sim journal log --path <journal> --index <N> --action tap --target "Sign In" \
  --coords "196,400" --before "abc12345" --before-name "Welcome" \
  --result navigated --after "def67890" --after-name "Login Form"
```

### 6. Get next instruction
```bash
agent-sim next --journal <path>
```

## Issue Detection

Flag an issue in the journal (`--issue "..."`) when:

| Signal | What it means |
|--------|---------------|
| Fingerprint changed but `explore` shows unexpected screen | **Wrong navigation** — tapping "Back" went to Home instead of parent |
| `assert --contains "label"` fails | **Missing element** — expected content is absent |
| `explore` returns 0 elements or shows SpringBoard | **Crash** — app terminated |
| Fingerprint unchanged after tapping interactive element | **Stuck** — element didn't respond |
| Interactive element has no label or identifier | **Accessibility gap** — missing a11y metadata |

## Verification

Use `assert` to verify expected state at any point:

```bash
# Check we're on the right screen
agent-sim assert --contains "Welcome" --not-contains "Error"

# Check screen identity
agent-sim assert --fingerprint "abc12345"

# Check minimum interactivity
agent-sim assert --min-interactive 3
```

Assert returns exit code 0 on pass, 1 on fail. JSON output includes all assertion results.

## Commands Reference

### Observation (read-only)
| Command | Use when | Output contains next command? |
|---------|----------|------|
| `next --journal <path>` | **Always start here.** Returns typed instruction. | Yes — `action.command` |
| `explore --annotate [--pretty]` | Need screen analysis + annotated screenshot + tap commands | Yes — `tap --box N` per element |
| `explore [--pretty]` | Need screen analysis without screenshot overhead | No — use labels or coordinates |
| `explore --screenshot <path>` | Need clean unannotated screenshot (design review) | No |
| `describe [--pretty\|--interactive]` | Need raw accessibility tree | No |
| `fingerprint [--hash-only]` | Need screen identity for transition detection | No |
| `status` | Need simulator/accessibility health check | No |
| `network [--errors] [--pretty]` | Need HTTP-level diagnostics (requires `launch --network`) | No |
| `screenshot [path]` | Need standalone screenshot | No |

### Action (modifies state)
| Command | Use when |
|---------|----------|
| `tap --box N` | **Preferred.** Tap element by box number from last `explore --annotate`. |
| `tap --label "text"` | Tap by accessibility label (when box mapping unavailable). |
| `tap --id "identifier"` | Tap by accessibility identifier. |
| `tap <x> <y>` | Tap by coordinates (last resort — fragile). |
| `swipe <direction>` | Swiping (up/down/left/right). |
| `type "text"` | Typing into a focused text field. |
| `launch <bundleId>` | Launching the app. |
| `launch --network <bundleId>` | Launching with HTTP diagnostics enabled. |
| `terminate <bundleId>` | Terminating the app. |

### Verification
| Command | Use when |
|---------|----------|
| `assert --contains "label"` | Checking element exists |
| `assert --not-contains "label"` | Checking element is absent |
| `assert --fingerprint "hash"` | Checking screen identity |
| `assert --screen-name "Home"` | Checking screen name |
| `assert --min-interactive N` | Checking minimum interactivity |

### Journaling
| Command | Use when |
|---------|----------|
| `journal init --path <path>` | Starting a new sweep |
| `journal log --path <path> ...` | Recording an action |
| `journal summary --path <path>` | Getting sweep stats |

## Network Debugging

When the agent sees an error on screen but doesn't know the underlying cause, use the `network` command to inspect HTTP-level activity.

**Setup:** Launch the app with `--network` to enable CFNetwork diagnostics:
```bash
agent-sim launch --network com.maddie.appnative
```

**Workflow:**
```bash
# 1. Agent sees error on screen via explore
agent-sim explore --annotate --pretty
# Output: "Something went wrong" dialog visible

# 2. Check what happened at the network level
agent-sim network --errors --pretty
# Output:
#   Network (last 30s) — 5 requests, 1 error
#     #3  12:31:49  PATCH /api/sessions/abc  409  (98ms)  ERROR

# 3. Now agent knows: 409 Conflict on PATCH /api/sessions — can diagnose the issue
```

**Flags:**
```bash
agent-sim network                   # Last 30s, all requests (JSON)
agent-sim network --errors          # Only failures (status >= 400)
agent-sim network --last 60         # Expand time window to 60s
agent-sim network --url "/sessions" # Filter by URL path
agent-sim network --pretty          # Human-readable table
```

If `network` returns no diagnostics, the app wasn't launched with `--network`. Relaunch:
```bash
agent-sim terminate com.maddie.appnative
agent-sim launch --network com.maddie.appnative
```

## Guardrails

These apply to every sweep. Violating them causes incorrect results.

1. **Copy commands from output** — do not construct commands from memory. Use `action.command` from `next`, or `tap --box N` from `explore --annotate`.
2. **Always use `next`** — do not decide what to tap on your own. The `next` command tracks what's been tapped and suggests the right next action.
3. **Journal every action** — do not batch. Each tap/swipe gets its own journal entry immediately.
4. **Fingerprint after every action** — this is how you detect screen transitions.
5. **Skip destructive elements** — Delete, Sign Out, Remove, etc. These kill the session.
6. **Do not type into text fields** — focus on tap interactions during exploration.
7. **Wait after tapping** — `sleep 1` before observing. UI needs time to settle.
8. **Dismiss modals before continuing** — sheets, alerts, and popovers must be closed before returning to parent screen traversal.
9. **If the app crashes, recover first** — log the crash, screenshot, relaunch, verify the screen, then continue.
10. **Scroll before declaring a screen exhausted** — `agent-sim swipe up` to check for off-screen content.
11. **Do not retry crashed actions** — if an action caused a crash, skip it and move on.

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
agent-sim status                          # Health check
agent-sim explore --annotate --pretty     # Observe screen + get tap commands
agent-sim tap --box 1                     # Act on element #1 from explore
agent-sim fingerprint --hash-only         # Detect transition
agent-sim next --journal build/sweep.md   # Get next instruction (guided mode)
```

The binary lives at `tools/AgentSim/.build/debug/AgentSim`. If it's not built yet,
build it first with `cd tools/AgentSim && swift build`.

## Output Format

All commands output JSON by default. Use `--pretty` for human-readable output.

**Key principle:** When `--pretty` output includes actionable elements, it also includes
the exact command to act on them. Copy the command — do not construct your own.

JSON contracts are stable. Field names will not change between versions.
