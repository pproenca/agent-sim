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

## Core Design: The `explore -i` + `tap @eN` Loop

The agent workflow is a simple observe-act loop. The agent uses `explore -i` to see
interactive elements with `@eN` refs, then `tap @eN` to act on them.

**How it works:**
1. `explore -i` reads the current screen via the AX API
2. Classifies elements and assigns `@eN` refs to interactive ones
3. Agent picks an element and runs `tap @eN`
4. Agent runs `explore -i` again to see what changed
5. Repeat until all reachable screens are covered

**Why this pattern works:**
- Agent gets exact refs to copy-paste — no coordinate construction
- Each `explore -i` shows screen name, element count, and fingerprint for navigation tracking
- Refs refresh each call — always accurate to current screen state
- No external state to manage — the screen IS the state

See `AGENTS.md` for full agent instructions.

## CLI Commands

### Flat (top-level)

| Command | Purpose | Output |
|---------|---------|--------|
| `explore` | Rich screen analysis — classified elements, fingerprint, suggested actions | JSON or `--pretty` |
| `explore -i` | Interactive elements with `@eN` refs | Text with refs |
| `explore --annotate` | Same as explore + annotated screenshot + `tap --box N` commands | JSON/pretty + PNG |
| `explore --screenshot <path>` | Same as explore + plain screenshot at given path | JSON/pretty + PNG |
| `explore --raw` | Raw accessibility tree | JSON or `--pretty` |
| `explore --fingerprint` | Screen identity hash for transition detection | Hash string |
| `explore --diff` | Show what changed since last explore | Diff output |
| `tap @eN` | **Preferred.** Tap by ref from last `explore -i` | "Done" |
| `tap --box N` | Tap by box number from last `explore --annotate` | "Done" |
| `tap --label "Sign In"` | Tap by accessibility label | "Done" |
| `tap --id "login.button"` | Tap by accessibility identifier | "Done" |
| `tap <x> <y>` | Tap at coordinates | "Done" |
| `swipe <up\|down\|left\|right>` | Swipe gesture | "Done" |
| `type "hello"` | Type text into focused field | "Done" |
| `screenshot [path]` | Capture PNG | File path |
| `launch <bundleId>` | Launch app | JSON |
| `stop <bundleId>` | Stop running app | JSON |
| `doctor` | Simulator + accessibility health check | Text |
| `update` | Update agent-sim to latest version | Text |

### Nested: `sim`

| Command | Purpose | Output |
|---------|---------|--------|
| `sim boot [name]` | Boot a simulator by name/UDID. Waits until usable. | JSON: udid, name, screen size |
| `sim list` | List available simulators | Text list |
| `sim shutdown` | Shut down the booted simulator | JSON |
| `sim install <path>` | Install .app or .ipa. Returns bundle ID. | JSON: bundleID, name |
| `sim apps [--pretty]` | List installed apps | JSON array |

### Nested: `ui`

| Command | Purpose | Output |
|---------|---------|--------|
| `ui assert visible "label"` | Verify element exists on screen | Exit 0/1 |
| `ui assert hidden "label"` | Verify element is absent | Exit 0/1 |
| `ui assert text "content"` | Verify text content | Exit 0/1 |
| `ui assert enabled "label"` | Verify element is enabled | Exit 0/1 |
| `ui wait [--timeout N]` | Block until screen is AX-ready. Replaces `sleep`. | JSON: ready, elementCount |
| `ui find "query"` | Find elements matching a query | JSON array |

### Nested: `config`

| Command | Purpose | Output |
|---------|---------|--------|
| `config set -S "iPhone 16"` | Save project settings | JSON |
| `config show` | Show current configuration | JSON |

### Nested: `project`

| Command | Purpose | Output |
|---------|---------|--------|
| `project context` | Show project context | Text |

All observation commands output JSON by default (for AI agent consumption). Human-readable
output via `--pretty` flag.

## Agent Workflow

See [AGENTS.md](AGENTS.md) for the canonical agent workflow.

The `explore -i` + `tap @eN` loop is the core interaction pattern. The cold-start flow:

```bash
agent-sim sim boot "iPhone 16"       # Boot + wait until usable
agent-sim sim install path/to/App.app # Install, returns bundle ID
agent-sim launch com.example.myapp   # Launch the app
agent-sim ui wait                    # Wait until screen is ready
agent-sim explore -i                 # Start the loop
```

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
the macOS window). Without scaling, coordinates from `explore --raw` would miss when passed
to `tap`.

Device screen size is auto-detected from the booted simulator's device type via
`simctl list devices booted`. A lookup table maps device type identifiers to known
screen sizes, with iPhone 16 (393×852) as the default fallback.

All coordinates exposed to the user are in **device-point space** — the same coordinate
system the iOS app uses. Coordinates from `explore`, `explore --raw`, or `tap --label` can
be passed directly to `tap <x> <y>` with no conversion.

## Why Not Just Use XcodeBuildMCP?

XcodeBuildMCP is an MCP server for build/test/debug workflows. AgentSim is a CLI tool
for exploratory QA. They serve different purposes and **should not be mixed** for
simulator interaction:

| | AgentSim | XcodeBuildMCP |
|---|---|---|
| **Transport** | CLI (Bash) — works in any context | MCP protocol — Claude Code only |
| **Coordinate space** | Device points (auto-scaled) | Device points (native) |
| **QA intelligence** | Element classification, fingerprinting, `@eN` refs | None — raw UI tree |
| **Overhead** | Direct function call (AXeCore linked in-process) | MCP protocol round-trip per action |

**The problem with mixing them:** AgentSim's `explore -i` provides `@eN` refs that map
to specific elements on the current screen. If you read elements from XcodeBuildMCP and
tap with AgentSim (or vice versa), coordinate spaces differ and taps will miss.

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
        ├── Explore.swift           # Rich screen observation with classification, --raw, --fingerprint, --diff
        ├── Tap.swift               # Tap by ref/coords/label/id (via AXeCore HID)
        ├── Swipe.swift             # Swipe gesture (via AXeCore HID)
        ├── TypeText.swift          # Keyboard input (via AXeCore HID)
        ├── Screenshot.swift        # Screen capture (xcrun simctl io)
        ├── Launch.swift            # App launch (xcrun simctl)
        ├── Stop.swift              # App stop (xcrun simctl)
        ├── Doctor.swift            # Health check
        ├── Sim.swift               # sim boot/list/shutdown/install/apps
        ├── UI.swift                # ui assert/wait/find
        ├── Config.swift            # config set/show
        └── Project.swift           # project context

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
