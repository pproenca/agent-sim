# agent-sim CLI v2 — Full Lifecycle Design

## Goal

Transform agent-sim from a UI-simulation-only CLI into a full lifecycle tool for Claude Code to build, test, run, and interact with iOS apps — no xcodebuild, no simctl, no FlowDeck needed.

## Key Decisions

1. **Full lifecycle CLI** — add build/test/run alongside existing UI simulation
2. **Direct Xcode framework linking** — link IDEFoundation, DVTFoundation from Xcode.app (same pattern as FBSimulatorControl for HID)
3. **FlowDeck-style hybrid namespacing** — flat for frequent commands, nested for management
4. **Config persistence** — `config set` saves defaults, subsequent commands are zero-flag
5. **Remove next/journal** — agents orchestrate explore/tap/assert themselves
6. **Keep `agent-sim` name** — established brand, 32 GitHub stars

## Command Taxonomy

### Flat Commands (frequent, agent-optimized)

| Command | Purpose | Output |
|---------|---------|--------|
| `build` | Compile for simulator/device | NDJSON progress + result |
| `run` | Build + launch on simulator/device | NDJSON + app running |
| `test` | Run unit/UI tests | NDJSON test events + result |
| `explore` | Rich screen analysis with element classification | JSON ScreenAnalysis |
| `tap` | Tap by label/id/coords/box number | JSON action result |
| `swipe` | Swipe gesture (up/down/left/right) | JSON action result |
| `type` | Type text into focused field | JSON action result |
| `screenshot` | Capture PNG | File path |
| `logs` | Stream app logs | NDJSON log events |
| `stop` | Terminate running app | JSON status |
| `doctor` | Health check (Xcode, simulator, frameworks) | Text/JSON |
| `update` | Self-update | Text |

### Nested Commands (management)

| Command | Purpose | Output |
|---------|---------|--------|
| `config set` | Save workspace/scheme/simulator defaults | JSON confirmation |
| `config show` | Show current config | JSON config |
| `sim list` | List simulators (filterable by platform) | JSON array |
| `sim boot` | Boot simulator, wait until usable | JSON: udid, name, screen size |
| `sim shutdown` | Shutdown simulator | JSON status |
| `sim erase` | Reset simulator to clean state | JSON status |
| `sim create` | Create new simulator | JSON: udid, name |
| `sim install` | Install .app/.ipa | JSON: bundleID, name |
| `sim apps` | List installed/running apps | JSON array |
| `project context` | Discover schemes, configs, simulators | JSON project info |
| `project schemes` | List available schemes | JSON array |
| `ui assert visible` | Assert element is visible | exit 0/1 + JSON |
| `ui assert hidden` | Assert element is absent | exit 0/1 + JSON |
| `ui assert text` | Assert element text content | exit 0/1 + JSON |
| `ui assert enabled` | Assert element is enabled | exit 0/1 + JSON |
| `ui wait` | Wait for element state (replaces sleep) | JSON: ready, duration |
| `ui find` | Find elements by label/id/role query | JSON array |

### Removed Commands (vs v1)

| Removed | Replacement |
|---------|-------------|
| `next` | Agent orchestrates explore/tap/assert itself |
| `journal init/log/summary` | Agent tracks state itself |
| `init` | `config set` |
| `boot` | `sim boot` |
| `apps` | `sim apps` or `project context` |
| `wait` | `ui wait` |
| `assert` | `ui assert *` |
| `use` | `config set` |
| `install` | `sim install` or `run` (auto-installs) |
| `describe` | `explore --raw` |
| `fingerprint` | `explore --fingerprint` |
| `diff` | `explore --diff <baseline>` |
| `network` | `logs --filter network` (if needed) |
| `launch` | `run --no-build` |
| `terminate` | `stop` |
| `status` | `doctor` (expanded) |

### Merged into `explore`

The `explore` command absorbs several v1 commands as flags:

```bash
agent-sim explore                    # Rich analysis (default)
agent-sim explore --annotate         # + annotated screenshot + box numbers
agent-sim explore --raw              # Raw AX tree (was: describe)
agent-sim explore --fingerprint      # Just the screen hash
agent-sim explore --diff <file>      # Diff against baseline
agent-sim explore --interactive      # Interactive ref-based (was: describe -i)
```

## Global Flags

Every command supports:

| Flag | Short | Purpose |
|------|-------|---------|
| `--json` | `-j` | NDJSON output (machine-readable) |
| `--verbose` | `-v` | Detailed output |
| `--examples` | `-e` | Show usage examples for this command |
| `--config` | `-c` | Load config from file path |

## Config System

```bash
# Save defaults (persists to .agent-sim/config.json in project root)
agent-sim config set -w MyApp.xcworkspace -s MyApp -S "iPhone 16"

# Override per-command
agent-sim build -C Release
agent-sim test -S "iPad Pro"

# Show current config
agent-sim config show
```

Config file format:
```json
{
  "workspace": "MyApp.xcworkspace",
  "scheme": "MyApp",
  "simulator": "iPhone 16",
  "configuration": "Debug"
}
```

Resolution order: CLI flag > config file > auto-detection.

## Build Engine Architecture

### Framework Linking

Link private Xcode frameworks from `/Applications/Xcode.app/Contents/Frameworks/`:

| Framework | Purpose |
|-----------|---------|
| `DVTFoundation` | Base types, file system, logging, plugin infrastructure |
| `IDEFoundation` | Workspace, project, scheme, build operation management |
| `IDEBuildEngine` | Build system interface |

Same approach as existing FBSimulatorControl/FBControlCore linking — either pre-built xcframeworks or direct dylib with `@rpath` to Xcode.app.

### BuildEngine Abstraction

```swift
// Mirrors SimulatorBridge pattern
struct BuildEngine {
    func discoverProject(at path: String) async throws -> ProjectContext
    func build(scheme: String, config: String, destination: Destination) async throws -> AsyncStream<BuildEvent>
    func test(scheme: String, only: [String]?, skip: [String]?) async throws -> AsyncStream<TestEvent>
    func run(scheme: String, destination: Destination) async throws -> RunResult
}
```

### Output Format

All build/test commands emit NDJSON:

```jsonl
{"type":"status","stage":"RESOLVING","message":"Resolving package dependencies..."}
{"type":"status","stage":"COMPILING","message":"Compiling AppDelegate.swift"}
{"type":"status","stage":"LINKING","message":"Linking MyApp"}
{"type":"result","success":true,"duration":4.2,"warnings":0,"errors":0}
```

Test events:
```jsonl
{"type":"test_started","suite":"LoginTests","name":"testValidLogin"}
{"type":"test_passed","suite":"LoginTests","name":"testValidLogin","duration":0.023}
{"type":"test_failed","suite":"LoginTests","name":"testBadPassword","message":"XCTAssertEqual failed: (\"error\") is not equal to (\"success\")","file":"LoginTests.swift","line":42}
{"type":"result","success":false,"passed":41,"failed":1,"skipped":0,"total":42,"duration":12.5}
```

## Typical Agent Workflow

```bash
# 1. Discover project
agent-sim project context --json

# 2. Save config (once per project)
agent-sim config set -w MyApp.xcworkspace -s MyApp -S "iPhone 16"

# 3. Build + run
agent-sim run

# 4. Explore the running app
agent-sim explore --annotate

# 5. Interact
agent-sim tap --label "Sign In"
agent-sim type "user@example.com"
agent-sim tap --label "Password"
agent-sim type "secret123"
agent-sim tap --label "Submit"

# 6. Assert
agent-sim ui assert visible "Welcome"

# 7. Run tests
agent-sim test --only LoginTests --json
```

## Implementation Phases

### Phase 1 — CLI Restructuring (no new features)

Reorganize existing commands into the new taxonomy:
- Move `boot` → `sim boot`, `apps` → `sim apps`
- Create `config set/show` (absorb `use` + `init`)
- Move `assert` → `ui assert visible/hidden/text/enabled`
- Move `wait` → `ui wait`
- Merge `describe` into `explore --raw`, `fingerprint` into `explore --fingerprint`
- Remove `next`, `journal`, `init`, `use`, `status`
- Rename `launch` → `run --no-build`, `terminate` → `stop`
- Add global `--json`, `--verbose`, `--examples` flags

### Phase 2 — Xcode Framework Discovery

- Locate and link IDEFoundation/DVTFoundation from Xcode.app
- Build `BuildEngine` abstraction (parallel to `SimulatorBridge`)
- Implement `project context` (read-only, low-risk starting point)
- Implement `doctor` to validate Xcode framework availability

### Phase 3 — Build/Test/Run

- `build` — drive compilation via IDEFoundation, stream NDJSON
- `test` — drive test execution, parse results for structured output
- `run` — build + launch (combines new build with existing sim launch)
- `logs` — stream app output
- `stop` — terminate app (existing `terminate` renamed)

### Phase 4 — Polish

- `--examples` flag with real examples on every command
- Config auto-detection (find .xcworkspace, pick default scheme/simulator)
- `sim create/erase` commands
- Error messages with actionable suggestions
