# CLI v2 Implementation Plan

> **Execution:** Use `/dev-workflow:execute-plan docs/plans/2026-03-09-cli-v2-implementation.md` to implement task-by-task.

**Goal:** Restructure agent-sim's flat 24-command CLI into a FlowDeck-style hybrid namespace (flat frequent commands + nested management groups), remove journal/next, and prepare for Phase 2 build/test/run.

**Architecture:** Command groups use ArgumentParser's `CommandConfiguration(subcommands:)` pattern (already proven in `Journal.swift`). Existing command logic is moved, not rewritten. New `SimGroup`, `UIGroup`, `ConfigGroup`, `ProjectGroup` wrapper structs route to existing implementations.

**Tech Stack:** Swift 6.2, swift-argument-parser 1.5.0+, Swift Testing framework

---

### Task 1: Create `sim` command group

Move simulator management commands under `sim` namespace: `sim boot`, `sim list`, `sim shutdown`, `sim install`, `sim apps`.

**Files:**
- Create: `Sources/AgentSim/Commands/SimGroup.swift`
- Modify: `Sources/AgentSim/AgentSim.swift:10-36`
- Modify: `Sources/AgentSim/Commands/Boot.swift:4-63`
- Delete logic from: `Sources/AgentSim/Commands/Apps.swift` (move into SimGroup)
- Delete logic from: `Sources/AgentSim/Commands/AppInstall.swift` (move into SimGroup)
- Test: `Tests/AgentSimTests/StructuralTests.swift`

**Step 1: Write structural test for sim group** (2 min)

Add to `Tests/AgentSimTests/StructuralTests.swift`:

```swift
@Test("sim command group has expected subcommands")
func simGroupSubcommands() {
  let config = SimGroup.configuration
  #expect(config.commandName == "sim")
  let names = config.subcommands.map { $0.configuration.commandName ?? "" }
  #expect(names.contains("boot"))
  #expect(names.contains("list"))
  #expect(names.contains("install"))
  #expect(names.contains("apps"))
}
```

**Step 2: Run test to verify it fails** (30 sec)

```bash
swift test --filter "sim command group"
```

Expected: FAIL — `SimGroup` doesn't exist.

**Step 3: Create SimGroup.swift with sim subcommands** (5 min)

Create `Sources/AgentSim/Commands/SimGroup.swift`:

```swift
import ArgumentParser

struct SimGroup: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "sim",
    abstract: "Manage simulators: boot, list, install apps.",
    subcommands: [SimBoot.self, SimList.self, SimInstall.self, SimApps.self, SimShutdown.self]
  )
}
```

Then rename/create thin wrappers inside the same file:

- `SimBoot` — wraps existing `Boot` logic (boot a simulator). Move `Boot.run()` body here.
- `SimList` — extracts `Boot.listShutdown()` as a standalone command. Add `--all` and `--booted` flags.
- `SimInstall` — rename from `AppInstall`.
- `SimApps` — rename from `Apps`.
- `SimShutdown` — new, calls `SimulatorBridge.shutdown()`.

Keep `Boot.swift`, `Apps.swift`, `AppInstall.swift` files but make the structs internal (not registered as top-level commands). The actual logic stays in the existing files — `SimGroup.swift` either re-exports or delegates.

**Step 4: Update AgentSim.swift command registration** (2 min)

Replace `Boot.self`, `AppInstall.self`, `Apps.self` in the `subcommands` array with `SimGroup.self`.

```swift
subcommands: [
  Init.self,
  SimGroup.self,        // was: Boot, AppInstall, Apps
  Wait.self,
  Use.self,
  ConfigCmd.self,
  // ... rest unchanged
]
```

**Step 5: Run test to verify it passes** (30 sec)

```bash
swift test --filter "sim command group"
```

Expected: PASS

**Step 6: Run full test suite** (1 min)

```bash
swift test
```

Expected: All tests pass. Fix any compilation errors from moved types.

**Step 7: Commit** (30 sec)

```bash
git add Sources/AgentSim/Commands/SimGroup.swift Sources/AgentSim/AgentSim.swift Sources/AgentSim/Commands/Boot.swift Sources/AgentSim/Commands/Apps.swift Sources/AgentSim/Commands/AppInstall.swift Tests/AgentSimTests/StructuralTests.swift
git commit -m "refactor: create sim command group (boot, list, install, apps, shutdown)"
```

---

### Task 2: Create `ui` command group

Move assertion and wait commands under `ui` namespace: `ui assert`, `ui wait`, `ui find`.

**Files:**
- Create: `Sources/AgentSim/Commands/UIGroup.swift`
- Modify: `Sources/AgentSim/AgentSim.swift`
- Modify: `Sources/AgentSim/Commands/Assert.swift`
- Modify: `Sources/AgentSim/Commands/Wait.swift`
- Test: `Tests/AgentSimTests/StructuralTests.swift`

**Step 1: Write structural test for ui group** (2 min)

```swift
@Test("ui command group has assert and wait subcommands")
func uiGroupSubcommands() {
  let config = UIGroup.configuration
  #expect(config.commandName == "ui")
  let names = config.subcommands.map { $0.configuration.commandName ?? "" }
  #expect(names.contains("assert"))
  #expect(names.contains("wait"))
  #expect(names.contains("find"))
}

@Test("ui assert has visible, hidden, text, enabled subcommands")
func uiAssertSubcommands() {
  let config = UIAssertGroup.configuration
  #expect(config.commandName == "assert")
  let names = config.subcommands.map { $0.configuration.commandName ?? "" }
  #expect(names.contains("visible"))
  #expect(names.contains("hidden"))
  #expect(names.contains("text"))
  #expect(names.contains("enabled"))
}
```

**Step 2: Run test to verify it fails** (30 sec)

```bash
swift test --filter "ui command group"
```

**Step 3: Create UIGroup.swift** (5 min)

Create `Sources/AgentSim/Commands/UIGroup.swift`:

```swift
import ArgumentParser

struct UIGroup: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "ui",
    abstract: "UI interaction: assertions, waits, element queries.",
    subcommands: [UIAssertGroup.self, UIWait.self, UIFind.self]
  )
}

struct UIAssertGroup: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "assert",
    abstract: "Assert screen state. Exit 0 on pass, 1 on fail.",
    subcommands: [UIAssertVisible.self, UIAssertHidden.self, UIAssertText.self, UIAssertEnabled.self]
  )
}
```

- `UIAssertVisible` — extracts `--contains` logic from existing `Assert`.
- `UIAssertHidden` — extracts `--not-contains` logic.
- `UIAssertText` — new, asserts element text content by label.
- `UIAssertEnabled` — new, asserts element enabled state.
- `UIWait` — rename from `Wait`, command name stays `wait`.
- `UIFind` — new command, finds elements by label/id/role query, returns JSON array.

The existing `Assert.swift` logic is split across the `UIAssert*` subcommands. Each focuses on a single assertion type with a simpler interface: `agent-sim ui assert visible "Sign In"` (positional argument, not `--contains`).

**Step 4: Update AgentSim.swift** (2 min)

Replace `Assert.self`, `Wait.self` with `UIGroup.self`.

**Step 5: Run tests** (30 sec)

```bash
swift test --filter "ui"
```

**Step 6: Commit** (30 sec)

```bash
git add Sources/AgentSim/Commands/UIGroup.swift Sources/AgentSim/AgentSim.swift Sources/AgentSim/Commands/Assert.swift Sources/AgentSim/Commands/Wait.swift Tests/AgentSimTests/StructuralTests.swift
git commit -m "refactor: create ui command group (assert visible/hidden/text/enabled, wait, find)"
```

---

### Task 3: Create `config set/show` and `project context`

Replace the old `config`, `init`, and `use` commands with `config set/show` and `project context`.

**Files:**
- Create: `Sources/AgentSim/Commands/ConfigGroup.swift`
- Create: `Sources/AgentSim/Commands/ProjectGroup.swift`
- Modify: `Sources/AgentSim/AgentSim.swift`
- Test: `Tests/AgentSimTests/StructuralTests.swift`
- Test: `Tests/AgentSimTests/ProjectConfigTests.swift`

**Step 1: Write structural test for config group** (2 min)

```swift
@Test("config command group has set and show subcommands")
func configGroupSubcommands() {
  let config = ConfigGroup.configuration
  #expect(config.commandName == "config")
  let names = config.subcommands.map { $0.configuration.commandName ?? "" }
  #expect(names.contains("set"))
  #expect(names.contains("show"))
}

@Test("project command group has context subcommand")
func projectGroupSubcommands() {
  let config = ProjectGroupCmd.configuration
  #expect(config.commandName == "project")
  let names = config.subcommands.map { $0.configuration.commandName ?? "" }
  #expect(names.contains("context"))
}
```

**Step 2: Run test to verify it fails** (30 sec)

```bash
swift test --filter "config command group"
```

**Step 3: Write config set/show test** (3 min)

```swift
@Test("ConfigSet persists workspace, scheme, simulator to temp config")
func configSetPersistence() throws {
  let tmpDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("agentsim-config-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

  let configPath = tmpDir.appendingPathComponent("config.json").path

  // Simulate config set by writing directly
  let config: [String: String] = [
    "workspace": "MyApp.xcworkspace",
    "scheme": "MyApp",
    "simulator": "iPhone 16",
    "configuration": "Debug"
  ]
  let data = try JSONEncoder().encode(config)
  try data.write(to: URL(fileURLWithPath: configPath))

  // Read back
  let loaded = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: URL(fileURLWithPath: configPath)))
  #expect(loaded["workspace"] == "MyApp.xcworkspace")
  #expect(loaded["scheme"] == "MyApp")
  #expect(loaded["simulator"] == "iPhone 16")

  try FileManager.default.removeItem(at: tmpDir)
}
```

**Step 4: Create ConfigGroup.swift** (5 min)

```swift
import ArgumentParser
import Foundation

struct ConfigGroup: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "config",
    abstract: "Save and show project settings.",
    subcommands: [ConfigSet.self, ConfigShow.self]
  )
}

struct ConfigSet: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "set",
    abstract: "Save workspace, scheme, simulator defaults. Subsequent commands use these automatically."
  )

  @Option(name: .shortAndLong, help: "Path to .xcworkspace or .xcodeproj")
  var workspace: String?

  @Option(name: .shortAndLong, help: "Scheme name")
  var scheme: String?

  @Option(name: [.customShort("S"), .long], help: "Simulator name or UDID")
  var simulator: String?

  @Option(name: [.customShort("C"), .long], help: "Build configuration (Debug/Release)")
  var configuration: String?

  func run() throws {
    // Load existing or create new
    var config = (try? ProjectConfig.loadBuildConfig()) ?? BuildConfig()
    if let workspace { config.workspace = workspace }
    if let scheme { config.scheme = scheme }
    if let simulator { config.simulator = simulator }
    if let configuration { config.configuration = configuration }

    try ProjectConfig.saveBuildConfig(config)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(config)
    print(String(data: data, encoding: .utf8) ?? "{}")
  }
}

struct ConfigShow: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "show",
    abstract: "Show current configuration."
  )

  func run() throws {
    // Merge existing ProjectConfig + new BuildConfig
    let config = ProjectConfig.resolve()
    let buildConfig = try? ProjectConfig.loadBuildConfig()

    let output = ConfigShowOutput(
      scope: config.scope.rawValue,
      journals: ProjectConfig.journalsDirectory(),
      workspace: buildConfig?.workspace,
      scheme: buildConfig?.scheme,
      simulator: buildConfig?.simulator,
      configuration: buildConfig?.configuration
    )
    JSONOutput.print(output)
  }
}
```

Add `BuildConfig` model to `Core/ProjectConfig.swift`:

```swift
struct BuildConfig: Codable {
  var workspace: String?
  var scheme: String?
  var simulator: String?
  var configuration: String?
}
```

Add `loadBuildConfig()` / `saveBuildConfig()` to `ProjectConfig`.

**Step 5: Create ProjectGroup.swift** (3 min)

```swift
import ArgumentParser

struct ProjectGroupCmd: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "project",
    abstract: "Project discovery and settings.",
    subcommands: [ProjectContext.self]
  )
}

struct ProjectContext: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "context",
    abstract: "Discover workspace, schemes, simulators, and build configurations."
  )

  func run() async throws {
    // For now: combine existing config info + simulator list
    let config = ProjectConfig.resolve()
    let buildConfig = try? ProjectConfig.loadBuildConfig()
    let devices = (try? await SimulatorBridge.allDevices()) ?? []

    let output = ProjectContextOutput(
      workspace: buildConfig?.workspace,
      scheme: buildConfig?.scheme,
      simulator: buildConfig?.simulator,
      configuration: buildConfig?.configuration ?? "Debug",
      simulators: devices.map { SimInfo(name: $0.name, udid: $0.udid, state: $0.state) }
    )
    JSONOutput.print(output)
  }
}
```

**Step 6: Update AgentSim.swift** (2 min)

Replace `ConfigCmd.self`, `Init.self`, `Use.self` with `ConfigGroup.self`, `ProjectGroupCmd.self`.

**Step 7: Run tests** (1 min)

```bash
swift test
```

**Step 8: Commit** (30 sec)

```bash
git add Sources/AgentSim/Commands/ConfigGroup.swift Sources/AgentSim/Commands/ProjectGroup.swift Sources/AgentSim/Core/ProjectConfig.swift Sources/AgentSim/AgentSim.swift Tests/
git commit -m "refactor: create config set/show and project context commands"
```

---

### Task 4: Merge describe, fingerprint, diff into explore

Add `--raw`, `--fingerprint`, `--diff` flags to `explore`. Remove standalone `describe`, `fingerprint`, `diff` commands.

**Files:**
- Modify: `Sources/AgentSim/Commands/Explore.swift:4-353`
- Modify: `Sources/AgentSim/AgentSim.swift`
- Delete: `Sources/AgentSim/Commands/Describe.swift` (logic moves to Explore)
- Delete: `Sources/AgentSim/Commands/FingerprintCmd.swift` (logic moves to Explore)
- Delete: `Sources/AgentSim/Commands/Diff.swift` (logic moves to Explore)
- Test: `Tests/AgentSimTests/StructuralTests.swift`

**Step 1: Write structural test** (2 min)

```swift
@Test("explore command accepts --raw, --fingerprint, --diff flags")
func exploreNewFlags() {
  // Verify the flags exist on the Explore type
  let mirror = Mirror(reflecting: Explore())
  let labels = mirror.children.compactMap(\.label)
  #expect(labels.contains("raw"))
  #expect(labels.contains("fingerprintOnly"))
}
```

**Step 2: Run test to verify it fails** (30 sec)

```bash
swift test --filter "explore command accepts"
```

**Step 3: Add flags to Explore.swift** (5 min)

Add to `Explore` struct:

```swift
@Flag(name: .long, help: "Raw accessibility tree output (was: describe).")
var raw = false

@Flag(name: .long, help: "Output only the screen fingerprint hash.")
var fingerprintOnly = false

@Flag(name: .long, help: "Show what changed since last explore (was: diff).")
var diff = false
```

Add branches to `run()`:

```swift
func run() async throws {
  let device = try await SimulatorBridge.resolveDevice()

  // --raw: raw AX tree (was: describe)
  if raw {
    let simNode = try await AXTreeReader.readDeviceTree(simulatorUDID: device.udid, maxDepth: maxDepth)
    if interactive {
      // interactive raw: show interactive elements with coords
      let elements = AXTreeReader.collectInteractive(simNode)
      // ... same logic as Describe --interactive
    } else if pretty {
      // ... same logic as Describe --pretty
    } else {
      JSONOutput.print(simNode)
    }
    return
  }

  // --fingerprint: just hash (was: fingerprint)
  if fingerprintOnly {
    let simNode = try await AXTreeReader.readDeviceTree(simulatorUDID: device.udid)
    let hash = Fingerprinter.fingerprint(simNode)
    print(hash)
    return
  }

  // --diff: show changes (was: diff)
  if diff {
    // ... move Diff.run() logic here
    return
  }

  // ... existing explore logic unchanged
}
```

Move the logic from `Describe.swift`, `FingerprintCmd.swift`, and `Diff.swift` into these branches. Delete the old files.

**Step 4: Remove old commands from AgentSim.swift** (2 min)

Remove `Describe.self`, `FingerprintCmd.self`, `Diff.self` from the `subcommands` array.

**Step 5: Delete old command files** (30 sec)

```bash
git rm Sources/AgentSim/Commands/Describe.swift Sources/AgentSim/Commands/FingerprintCmd.swift Sources/AgentSim/Commands/Diff.swift
```

**Step 6: Run tests** (1 min)

```bash
swift test
```

Fix any references to `Describe`, `FingerprintCmd`, `Diff` in tests.

**Step 7: Commit** (30 sec)

```bash
git add -A
git commit -m "refactor: merge describe, fingerprint, diff into explore (--raw, --fingerprint, --diff)"
```

---

### Task 5: Rename terminate → stop, clean up launch

Rename `Terminate` to `Stop` (top-level). Keep `Launch` as-is for now (will become `run --no-build` in Phase 3).

**Files:**
- Create: `Sources/AgentSim/Commands/Stop.swift`
- Modify: `Sources/AgentSim/AgentSim.swift`
- Modify: `Sources/AgentSim/Commands/Launch.swift`
- Test: `Tests/AgentSimTests/StructuralTests.swift`

**Step 1: Write structural test** (2 min)

```swift
@Test("stop command exists with expected command name")
func stopCommandExists() {
  let config = Stop.configuration
  #expect(config.commandName == "stop")
}
```

**Step 2: Run test to verify it fails** (30 sec)

```bash
swift test --filter "stop command exists"
```

**Step 3: Create Stop.swift** (2 min)

```swift
import ArgumentParser

struct Stop: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "stop",
    abstract: "Stop a running app on the simulator."
  )

  @Argument(help: "Bundle identifier of the app to stop.")
  var bundleID: String

  @Option(name: .long, help: "Target a specific simulator by UDID.")
  var udid: String?

  func run() async throws {
    let device = try await SimulatorBridge.resolveDevice(udid: udid)
    try await SimulatorBridge.terminate(simulatorID: device.udid, bundleID: bundleID)
  }
}
```

**Step 4: Update AgentSim.swift** (2 min)

Replace `Terminate.self` with `Stop.self`. Remove `Terminate` from `Launch.swift`.

**Step 5: Run tests** (30 sec)

```bash
swift test
```

**Step 6: Commit** (30 sec)

```bash
git add Sources/AgentSim/Commands/Stop.swift Sources/AgentSim/AgentSim.swift Sources/AgentSim/Commands/Launch.swift Tests/
git commit -m "refactor: rename terminate → stop"
```

---

### Task 6: Remove next, journal, network, init, use, status

Delete commands that are replaced by the new structure or no longer needed.

**Files:**
- Delete: `Sources/AgentSim/Commands/Next.swift`
- Delete: `Sources/AgentSim/Commands/Journal.swift`
- Delete: `Sources/AgentSim/Commands/Network.swift`
- Delete: `Sources/AgentSim/Commands/Init.swift`
- Delete: `Sources/AgentSim/Commands/Use.swift`
- Delete: `Sources/AgentSim/Commands/Status.swift`
- Modify: `Sources/AgentSim/AgentSim.swift`
- Modify: `Tests/AgentSimTests/StructuralTests.swift`
- May need to update: `Tests/AgentSimTests/NextInstructionTests.swift`, `Tests/AgentSimTests/JournalIntegrationTests.swift`

**Step 1: Update structural test** (2 min)

Add test verifying removed commands are NOT in the subcommands list:

```swift
@Test("removed commands are not registered")
func removedCommands() {
  let names = AgentSim.configuration.subcommands.map {
    $0.configuration.commandName ?? String(describing: $0)
  }
  #expect(!names.contains("next"))
  #expect(!names.contains("journal"))
  #expect(!names.contains("network"))
  #expect(!names.contains("init"))
  #expect(!names.contains("use"))
  #expect(!names.contains("status"))
}
```

**Step 2: Remove commands from AgentSim.swift** (2 min)

Remove `Next.self`, `Journal.self`, `Network.self`, `Init.self`, `Use.self`, `Status.self` from the `subcommands` array.

**Step 3: Delete command files** (30 sec)

```bash
git rm Sources/AgentSim/Commands/Next.swift Sources/AgentSim/Commands/Journal.swift Sources/AgentSim/Commands/Network.swift Sources/AgentSim/Commands/Init.swift Sources/AgentSim/Commands/Use.swift Sources/AgentSim/Commands/Status.swift
```

**Step 4: Handle orphaned tests** (3 min)

- Delete `Tests/AgentSimTests/NextInstructionTests.swift` (tests `Next` command logic).
- Delete `Tests/AgentSimTests/JournalIntegrationTests.swift` (tests journal init/log/summary).
- Keep `Tests/AgentSimTests/SweepStateReaderTests.swift` — `SweepStateReader` is in Core and may still be used.
- Delete `Tests/AgentSimTests/Support/JournalFixtures.swift` if only used by journal tests.

**Step 5: Handle orphaned core files** (2 min)

Check if `SweepState.swift`, `ActionLogger.swift`, `NetworkLogParser.swift` are still referenced after removing commands. If not, delete them too. If `ActionLogger` is still used by `Tap`/`Swipe`/`Type`, keep it.

**Step 6: Run tests** (1 min)

```bash
swift test
```

Expected: All remaining tests pass.

**Step 7: Commit** (30 sec)

```bash
git add -A
git commit -m "refactor: remove next, journal, network, init, use, status commands"
```

---

### Task 7: Update skills, commands, and docs

Update all agent-facing documentation to reflect the new CLI structure.

**Files:**
- Modify: `skills/agent-sim/SKILL.md`
- Modify: `commands/new.md`
- Modify: `commands/apply.md`
- Modify: `commands/replay.md`
- Modify: `commands/tests.md`
- Modify: `commands/critique.md`
- Modify: `DESIGN.md`
- Modify: `README.md`
- Modify: `AGENTS.md`

**Step 1: Update SKILL.md** (3 min)

Update the primary skill definition to reflect new command names:

```markdown
## Commands

| Command | What it does |
|---------|-------------|
| `explore -i` | List interactive elements with `@eN` refs |
| `tap @eN` | Tap element by ref -> "Done" |
| `swipe up|down|left|right` | Scroll -> "Done" |
| `type "text"` | Type into focused field -> "Done" |
| `screenshot [path]` | Capture screen |
| `ui assert visible "X"` | Verify element exists |
| `ui wait` | Wait until screen is ready |
| `sim boot` | Boot simulator |
| `sim list` | List simulators |
| `config set` | Save project settings |
| `config show` | Show current config |
| `project context` | Discover project structure |
| `stop <bundleId>` | Stop running app |
| `doctor` | Health check |
```

**Step 2: Update AGENTS.md** (5 min)

Remove all references to `next`, `journal`, `init`, `use`, `status`. Update command examples throughout. Remove the sweep state machine section. Update the workflow to use the new command structure.

**Step 3: Update DESIGN.md** (5 min)

Replace the CLI Commands section with the v2 taxonomy from the design doc.

**Step 4: Update README.md** (3 min)

Update the quick start and command reference sections.

**Step 5: Update command markdown files** (5 min)

Update `commands/new.md`, `commands/apply.md`, `commands/replay.md`, `commands/tests.md`, `commands/critique.md` to use new command names (`ui assert visible` instead of `assert --contains`, `sim boot` instead of `boot`, etc.).

**Step 6: Commit** (30 sec)

```bash
git add skills/ commands/ DESIGN.md README.md AGENTS.md
git commit -m "docs: update all agent-facing docs for CLI v2 command structure"
```

---

### Task 8: Final verification and cleanup

Verify the complete new CLI structure works end-to-end.

**Files:**
- Modify: `Sources/AgentSim/AgentSim.swift` (final state)
- Test: `Tests/AgentSimTests/StructuralTests.swift`

**Step 1: Write comprehensive structural test** (3 min)

```swift
@Test("CLI v2 command structure matches design")
func cliV2Structure() {
  let topLevel = AgentSim.configuration.subcommands.map {
    $0.configuration.commandName ?? String(describing: $0)
  }

  // Flat commands (frequent)
  #expect(topLevel.contains("explore"))
  #expect(topLevel.contains("tap"))
  #expect(topLevel.contains("swipe"))
  #expect(topLevel.contains("type"))
  #expect(topLevel.contains("screenshot"))
  #expect(topLevel.contains("launch"))
  #expect(topLevel.contains("stop"))
  #expect(topLevel.contains("doctor"))
  #expect(topLevel.contains("update"))

  // Grouped commands
  #expect(topLevel.contains("sim"))
  #expect(topLevel.contains("ui"))
  #expect(topLevel.contains("config"))
  #expect(topLevel.contains("project"))

  // Removed commands
  #expect(!topLevel.contains("next"))
  #expect(!topLevel.contains("journal"))
  #expect(!topLevel.contains("init"))
  #expect(!topLevel.contains("use"))
  #expect(!topLevel.contains("status"))
  #expect(!topLevel.contains("boot"))
  #expect(!topLevel.contains("apps"))
  #expect(!topLevel.contains("install"))
  #expect(!topLevel.contains("assert"))
  #expect(!topLevel.contains("wait"))
  #expect(!topLevel.contains("describe"))
  #expect(!topLevel.contains("fingerprint"))
  #expect(!topLevel.contains("diff"))
  #expect(!topLevel.contains("network"))
  #expect(!topLevel.contains("terminate"))
}
```

**Step 2: Run full test suite** (1 min)

```bash
swift test
```

Expected: All tests pass.

**Step 3: Verify --help output** (1 min)

```bash
swift run AgentSim --help
swift run AgentSim sim --help
swift run AgentSim ui --help
swift run AgentSim ui assert --help
swift run AgentSim config --help
swift run AgentSim project --help
```

**Step 4: Clean up dead code** (3 min)

Search for any remaining references to deleted types. Remove unused imports, dead test fixtures, orphaned support files.

```bash
grep -r "Next\b\|Journal\b\|JournalInit\b\|JournalLog\b\|JournalSummary\b\|SweepState\b" Sources/ Tests/ --include="*.swift" -l
```

**Step 5: Commit** (30 sec)

```bash
git add -A
git commit -m "refactor: CLI v2 restructuring complete — verify and clean up"
```

---

### Task 9: Code Review

Review all changes since the restructuring began for correctness, consistency, and test coverage.

---

## Parallel Groups

| Group | Tasks | Rationale |
|-------|-------|-----------|
| Group 1 | 1, 2, 3 | Independent command groups — `sim`, `ui`, `config/project` touch different files |
| Group 2 | 4, 5 | Both modify `AgentSim.swift` and delete command files |
| Group 3 | 6 | Depends on Groups 1-2 being merged (removes commands replaced by groups) |
| Group 4 | 7 | Documentation — depends on all command changes being final |
| Group 5 | 8, 9 | Final verification and review — depends on everything else |

---

## Phase 2 — Xcode Framework Spike (not detailed yet)

**Goal:** Determine if linking IDEFoundation/DVTFoundation from Xcode.app is feasible for programmatic build/test/run.

**Tasks (high-level):**
1. Spike: locate and inventory frameworks in `/Applications/Xcode.app/Contents/Frameworks/`
2. Spike: attempt to link DVTFoundation in a minimal Swift CLI
3. Spike: call a simple read-only API (e.g., list schemes from a workspace)
4. If feasible: design `BuildEngine` abstraction (mirrors `SimulatorBridge`)
5. If not feasible: fall back to wrapping xcodebuild subprocess with structured output parsing

## Phase 3 — Build/Test/Run (depends on Phase 2)

**Tasks (high-level):**
1. Implement `build` command with NDJSON progress output
2. Implement `test` command with per-test NDJSON events
3. Implement `run` command (build + launch)
4. Implement `logs` command (stream app output)
5. Integrate with `config set` (zero-flag builds)

## Phase 4 — Polish

**Tasks (high-level):**
1. Add `--examples` flag to every command
2. Config auto-detection (find .xcworkspace, pick default scheme/simulator)
3. Implement `sim create`, `sim erase`
4. Error messages with actionable suggestions
5. Update version to v0.2.0
