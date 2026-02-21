# AgentSim — Design

## What This Is

A Swift CLI tool that gives Claude Code (or any AI agent) the ability to explore an iOS app
running in the Simulator like a human QA tester, journal every action, detect issues, and
generate BDD-style acceptance tests.

## Spike Results (2026-02-20)

**Confirmed:** The macOS public Accessibility API (`AXUIElement`) fully exposes the iOS app's
accessibility tree through the Simulator process.

- Elements visible: roles, labels, identifiers, descriptions, frames, enabled state
- Coordinate mapping: screen-absolute → simulator-relative via window origin offset
- Depth: full tree traversal works (tested up to depth 20)
- Performance: tree read completes in <100ms for screens with ~20 elements

**What the public API gives us (no private frameworks):**
- Full UI tree inspection (AXUIElement traversal)
- Element attributes: role, label, identifier, value, description, enabled, frame
- Window geometry (for coordinate conversion)
- Process discovery (NSWorkspace)

**What still requires private frameworks or simctl:**
- Touch/gesture injection (no public API for this)
- Screenshots (`xcrun simctl io screenshot`)
- App lifecycle (launch, terminate via `xcrun simctl`)
- Keyboard input (HID events)

## Architecture Decision

**Hybrid approach — zero external dependencies:**
1. **UI tree reading** — macOS public AX API (stable, no private framework risk)
2. **Touch/swipe injection** — AXeCore library (linked via local Swift package, uses Facebook IDB frameworks)
3. **Keyboard input** — AXeCore library (HID key events)
4. **Screenshots** — `xcrun simctl io screenshot` (wrapped by SimulatorBridge)
5. **App lifecycle** — `xcrun simctl launch/terminate` (wrapped by SimulatorBridge)

The agent never calls `xcrun` or any other tool directly — SimulatorBridge wraps everything.
AXeCore is linked as a Swift package dependency (not shelled out to), so touch injection
has zero process spawn overhead.

**Coordinate pipeline:**
```
macOS AX API → screen-absolute coords
  → subtract window origin → simulator-relative (macOS window space)
  → scale by device/window ratio → device-point space (matches HID)
```
All coordinates exposed to the user are in device-point space. They work directly with
`agent-sim tap` — no manual conversion needed.

## Core Design: The `next` Command

Modeled after OpenSpec's `instructions` command — the single command that makes agent-driven
sweeps reliable. The agent never decides what to do; it asks `next` and follows the typed response.

**How it works:**
1. Reads the journal file to know what's been done
2. Reads the current screen via the AX API
3. Computes which elements are untapped
4. Returns a typed instruction with exact CLI command, afterAction steps, and guardrails

**Typed phases** (agent branches on this, never on free text):
- `not_started` — no journal exists, init one
- `new_screen` — screen not yet explored, start tapping
- `exploring` — known screen with untapped elements
- `screen_exhausted` — all elements tapped, navigate back
- `crashed` — app unresponsive, recover
- `complete` — all reachable screens explored

**Why this pattern works** (learned from OpenSpec):
- Agent gets exact CLI commands to copy-paste — no decision-making
- AfterAction steps are ordered — agent follows them sequentially
- Guardrails prevent common mistakes per phase
- Progress tracking is built in — screensVisited, totalActions, issuesFound
- Filesystem (journal) is source of truth — resumable, debuggable

See `AGENTS.md` for full agent instructions.

## CLI Commands

### Instruction (start here)

| Command | Purpose | Output |
|---------|---------|--------|
| `next --journal <path>` | **The core command.** Returns typed instruction: what to do, exact command, afterAction steps, guardrails. | JSON with `phase`, `action.command`, `afterAction[]`, `guardrails[]` |

### Observation

| Command | Purpose | Output |
|---------|---------|--------|
| `explore` | Rich screen analysis — classified elements, fingerprint, suggested actions | JSON or `--pretty` |
| `explore --annotate` | Same as above + annotated screenshot + `tap --box N` commands | JSON/pretty + PNG at default path |
| `explore --screenshot <path>` | Same as explore + plain (unannotated) screenshot at given path | JSON/pretty + PNG |
| `describe` | Raw accessibility tree | JSON or `--pretty` / `--interactive` |
| `fingerprint` | Screen identity hash for transition detection | `{hash} {screenName}` or `--hash-only` |
| `status` | Simulator + accessibility health check | Text |
| `screenshot [path]` | Capture PNG | File path |

### Action

| Command | Purpose |
|---------|---------|
| `tap --box N` | **Preferred.** Tap by box number from last `explore --annotate` |
| `tap <x> <y>` | Tap at coordinates |
| `tap --label "Sign In"` | Tap by accessibility label |
| `tap --id "login.button"` | Tap by accessibility identifier |
| `swipe <up\|down\|left\|right>` | Swipe gesture |
| `type "hello"` | Type text into focused field |
| `launch <bundleId>` | Launch app |
| `terminate <bundleId>` | Terminate app |

### Verification

| Command | Purpose |
|---------|---------|
| `assert --contains "label"` | Verify element exists on screen |
| `assert --not-contains "label"` | Verify element is absent |
| `assert --fingerprint "hash"` | Verify we're on expected screen |
| `assert --screen-name "Home"` | Verify screen name |
| `assert --min-interactive N` | Verify minimum interactive elements |

### Journaling

| Command | Purpose |
|---------|---------|
| `journal init [--path] [--simulator] [--scope]` | Create new sweep journal |
| `journal log [--path] --index N --action "..." --result "..."` | Append action entry |
| `journal summary [--path]` | Print journal stats (JSON) |

All observation commands output JSON by default (for AI agent consumption). Human-readable
output via `--pretty` flag.

## QA Cold-Start Workflow

The intended usage pattern for an AI agent doing QA exploration:

```
1. agent-sim launch <bundleId>          # Start the app
2. agent-sim explore --pretty           # Observe: what's on screen?
3. agent-sim journal init               # Start logging
4. agent-sim fingerprint --hash-only    # Record initial screen identity

# For each action:
5. agent-sim tap --label "Next"         # Act
6. agent-sim fingerprint --hash-only    # Check: did the screen change?
7. agent-sim explore                    # Observe the new screen
8. agent-sim assert --contains "..."    # Verify expected elements
9. agent-sim journal log --index 1 ...  # Journal the step

# After exploration:
10. agent-sim journal summary --path ... # Get stats
```

### Cognitive Steps (what the AI agent does at each screen)

1. **Observe** — `explore` to see all elements, classified by type
2. **Plan** — Read `suggestedActions` to decide what to tap next
3. **Act** — `tap` the chosen element
4. **Compare** — `fingerprint` to detect if the screen changed
5. **Verify** — `assert` to confirm expected outcome
6. **Journal** — `journal log` to record the step and any issues
7. **Repeat** — DFS: if new screen, recurse; if same screen, move to next element

### Issue Detection

The agent should flag issues when:
- **Wrong navigation**: Tapping "Back" navigated to Home instead of parent screen
- **Missing elements**: Expected screen content is absent (`assert --contains` fails)
- **Crash**: `explore` returns no elements or finds SpringBoard
- **Stuck**: Same fingerprint after tapping an interactive element
- **Accessibility gaps**: Interactive elements with no label or identifier

## Screen Analysis Model

The `explore` command returns a `ScreenAnalysis` object:

```json
{
  "fingerprint": "20b971e1890472d3",
  "screenName": "Onboarding",
  "elementCount": 12,
  "interactiveCount": 4,
  "tabs": [{"label": "Home", "tapX": 50, "tapY": 800, "isSelected": true}],
  "navigation": [{"name": "Back", "tapX": 20, "tapY": 50, ...}],
  "actions": [{"name": "Sign In", "tapX": 196, "tapY": 400, ...}],
  "content": [{"text": "Welcome", "frame": {...}}],
  "destructive": [{"name": "Delete Account", ...}],
  "disabled": [{"name": "Submit", ...}],
  "suggestedActions": [
    {"priority": 1, "action": "tap", "target": "Sign In", "reason": "Interactive AXButton"}
  ]
}
```

### Element Classification

Elements are sorted into buckets:
- **navigation** — Back/Close/Done/Cancel buttons near the top of the screen
- **actions** — Interactive elements that aren't navigation or destructive
- **destructive** — Delete, Sign Out, Remove, etc. (skipped during sweeps)
- **disabled** — Interactive elements with `enabled: false`
- **content** — Static text for context understanding

### Screen Fingerprinting

Hash computed from sorted list of `role|label|x|y|width|height` for all elements with
a label and frame. SHA-256, truncated to 16 hex chars. Two screens with the same
elements in the same positions produce the same fingerprint.

## Templates

Markdown templates in `Templates/` for structured output:

| Template | Purpose |
|----------|---------|
| `sweep-journal.md` | Running log of every action during exploration |
| `coverage-map.md` | Screens visited, navigation graph, unreached areas |
| `issue-report.md` | Bug/anomaly report with reproduction steps |
| `bdd-test.md` | BDD Given/When/Then specs from observed behavior |

## Coordinate System

The macOS AX API returns screen-absolute coordinates in macOS window points. AgentSim
converts through a two-step pipeline to produce device-point coordinates:

```
1. Subtract window origin:    simX = screenX - windowOriginX
2. Scale to device points:    devX = simX × (deviceWidth / windowWidth)
```

The window-to-device scaling is necessary because the Simulator renders the iOS device
at a scale factor on the Mac screen (e.g., iPhone 16's 393×852 renders as ~359×778 in
the macOS window). Without scaling, coordinates from `describe` would miss when passed
to `tap`.

Device screen size is auto-detected from the booted simulator's device type via
`simctl list devices booted`. A lookup table maps device type identifiers to known
screen sizes, with iPhone 16 (393×852) as the default fallback.

All coordinates exposed to the user are in **device-point space** — the same coordinate
system the iOS app uses. Coordinates from `describe`, `explore`, or `tap --label` can
be passed directly to `tap <x> <y>` with no conversion.

## Why Not Just Use XcodeBuildMCP?

XcodeBuildMCP is an MCP server for build/test/debug workflows. AgentSim is a CLI tool
for exploratory QA. They serve different purposes and **should not be mixed** for
simulator interaction:

| | AgentSim | XcodeBuildMCP |
|---|---|---|
| **Transport** | CLI (Bash) — works in any context | MCP protocol — Claude Code only |
| **Coordinate space** | Device points (auto-scaled) | Device points (native) |
| **QA intelligence** | Element classification, fingerprinting, journaling, state machine | None — raw UI tree |
| **Overhead** | Direct function call (AXeCore linked in-process) | MCP protocol round-trip per action |
| **Resumability** | Journal file = full state, resume any time | None |

**The problem with mixing them:** AgentSim's `next` command tracks which elements have
been tapped on which screens. If you tap via XcodeBuildMCP, AgentSim doesn't know about
it and gives wrong instructions. The journal has gaps. The sweep becomes unreliable.

**Rule:** Use XcodeBuildMCP for building and testing. Use AgentSim for everything that
involves driving the simulator UI. Never mix them for UI interaction in the same session.

## Source Layout

```
tools/AgentSim/
├── Package.swift                   # Depends on swift-argument-parser + AXeCore (local package)
├── DESIGN.md                       # Architecture + command docs
├── AGENTS.md                       # Instructions for AI agents using this CLI
├── Templates/
│   ├── sweep-journal.md            # Journal template
│   ├── coverage-map.md             # Coverage tracking template
│   ├── issue-report.md             # Bug report template
│   └── bdd-test.md                 # BDD test spec template
└── Sources/AgentSim/
    ├── AgentSim.swift              # Entry point, command registration
    ├── Core/
    │   ├── AXTreeReader.swift      # macOS AX API tree reader (device-space coordinates)
    │   ├── SimulatorBridge.swift   # AXeCore HID + xcrun simctl (screenshot/launch/terminate)
    │   ├── ScreenAnalysis.swift    # Screen analysis model + builder
    │   ├── Fingerprinter.swift     # Screen fingerprinting (SHA-256)
    │   └── SweepState.swift        # Typed sweep state machine + journal parser
    └── Commands/
        ├── Next.swift              # THE core command — typed instructions for agent
        ├── Explore.swift           # Rich screen observation with classification
        ├── Describe.swift          # Raw accessibility tree output
        ├── Tap.swift               # Tap by coords/label/id (via AXeCore HID)
        ├── Swipe.swift             # Swipe gesture (via AXeCore HID)
        ├── TypeText.swift          # Keyboard input (via AXeCore HID)
        ├── Screenshot.swift        # Screen capture (xcrun simctl io)
        ├── FingerprintCmd.swift    # Screen identity hash
        ├── Assert.swift            # State verification (exit 0/1)
        ├── Journal.swift           # Sweep journal init/log/summary
        ├── Launch.swift            # App launch + terminate (xcrun simctl)
        └── Status.swift            # Health check

tools/axe-source/
├── Sources/AXeCore/               # Library: HID interactor, key codes, IDB bridge
│   ├── HIDInteractor.swift         # Core HID event dispatch (tap, swipe, type)
│   ├── TextToHIDEvents.swift       # String → HID key event conversion
│   ├── KeyCode.swift               # Character ↔ HID keycode mapping
│   ├── FutureBridge.swift          # ObjC FBFuture → Swift async bridge
│   └── ...                         # Logger, queues, framework setup
├── Sources/AXe/                    # CLI executable (standalone, not used by AgentSim)
└── Frameworks/                     # Pre-built IDB XCFrameworks (FBSimulatorControl, etc.)
```
