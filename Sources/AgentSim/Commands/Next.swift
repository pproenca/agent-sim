import ArgumentParser
import Foundation

/// The "instructions" command — tells the agent EXACTLY what to do next.
/// Reads the journal + current screen state and returns a typed instruction.
///
/// Modeled after OpenSpec's `instructions` command:
/// - Typed phase (`not_started`, `exploring`, `new_screen`, `complete`, `crashed`)
/// - Exact CLI command to run
/// - Reason for the action
/// - Steps to take after the action
/// - Guardrails to prevent common mistakes
struct Next: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Get the next instruction for the QA sweep. Tells the agent exactly what to do."
  )

  @Option(name: .long, help: "Path to the sweep journal file.")
  var journal: String?

  @Option(name: .long, help: "Bundle ID of the app under test.")
  var bundleID: String?

  @Option(name: .long, help: "Maximum DFS depth.")
  var maxDepth: Int = 6

  @Option(name: .long, help: "Maximum unique screens to visit.")
  var maxScreens: Int = 80

  @Flag(name: .long, help: "Human-readable output instead of JSON.")
  var pretty = false

  func run() async throws {
    let instruction = try await buildInstruction()

    if pretty {
      printPretty(instruction)
    } else {
      printJSON(instruction)
    }
  }

  private func buildInstruction() async throws -> NextInstruction {
    // Phase 1: Check if journal exists
    guard let journalPath = journal else {
      return notStartedInstruction()
    }

    guard let journalState = SweepStateReader.readJournal(at: journalPath) else {
      return notStartedInstruction()
    }

    // Phase 2: Check if simulator is alive
    let device: SimulatorBridge.BootedDevice
    do {
      device = try await SimulatorBridge.resolveDevice()
    } catch {
      return crashedInstruction(
        reason: "\(error)",
        recovery: "agent-sim use \"<device name>\"",
        journalState: journalState,
        journalPath: journalPath
      )
    }

    let simNode: AXNode
    do {
      simNode = try await AXTreeReader.readDeviceTree(simulatorUDID: device.udid)
    } catch {
      return crashedInstruction(
        reason: "No app content found — app may have crashed or is on SpringBoard.",
        recovery: "agent-sim launch \(bundleID ?? "<bundleId>")",
        journalState: journalState,
        journalPath: journalPath
      )
    }
    let analysis = ScreenAnalyzer.analyze(simNode)

    // Phase 3: Check limits
    if journalState.screens.count >= maxScreens {
      return completeInstruction(
        reason: "Reached screen limit (\(maxScreens)).",
        journalState: journalState,
        journalPath: journalPath
      )
    }

    // Phase 4: Determine what to do on this screen
    let currentFingerprint = analysis.fingerprint
    let isNewScreen = !journalState.screens.contains(String(currentFingerprint.prefix(8)))

    // Find untapped elements
    let untapped = analysis.actions.filter { action in
      let key = "\(String(currentFingerprint.prefix(8))):\(action.name)"
      return !journalState.tappedElements.contains(key)
    }

    let screenSnapshot = NextInstruction.ScreenSnapshot(
      name: analysis.screenName,
      fingerprint: currentFingerprint,
      interactiveCount: analysis.interactiveCount,
      tappedCount: analysis.actions.count - untapped.count,
      remainingCount: untapped.count
    )

    let progress = NextInstruction.SweepProgress(
      screensVisited: journalState.screens.count,
      totalActions: journalState.totalActions,
      issuesFound: journalState.issues,
      crashesDetected: journalState.crashes,
      journalPath: journalPath
    )

    // Decide phase and action
    if isNewScreen && !untapped.isEmpty {
      // New screen with elements to tap
      let target = untapped[0]
      let actionIndex = journalState.totalActions + 1

      return NextInstruction(
        phase: .newScreen,
        instruction: "New screen discovered: \"\(analysis.screenName)\". Tap the first untapped element.",
        action: .init(
          type: "tap",
          target: target.name,
          command: "agent-sim tap --label \"\(target.name)\"",
          reason: "First untapped interactive element on new screen",
          tapX: target.tapX,
          tapY: target.tapY
        ),
        currentScreen: screenSnapshot,
        progress: progress,
        afterAction: [
          "sleep 1",
          "agent-sim fingerprint --hash-only",
          "agent-sim explore",
          "agent-sim journal log --path \(journalPath) --index \(actionIndex) --action tap --target \"\(target.name)\" --coords \"\(target.tapX),\(target.tapY)\" --before \"\(String(currentFingerprint.prefix(8)))\" --before-name \"\(analysis.screenName)\" --result <navigated|same-screen> --after <new-fingerprint> --after-name <new-screen-name>",
          "agent-sim next --journal \(journalPath)"
        ],
        guardrails: Self.standardGuardrails
      )
    } else if !untapped.isEmpty {
      // Known screen with untapped elements
      let target = untapped[0]
      let actionIndex = journalState.totalActions + 1

      return NextInstruction(
        phase: .exploring,
        instruction: "Continue exploring \"\(analysis.screenName)\". \(untapped.count) elements remaining.",
        action: .init(
          type: "tap",
          target: target.name,
          command: "agent-sim tap --label \"\(target.name)\"",
          reason: "\(untapped.count) untapped elements remain on this screen",
          tapX: target.tapX,
          tapY: target.tapY
        ),
        currentScreen: screenSnapshot,
        progress: progress,
        afterAction: [
          "sleep 1",
          "agent-sim fingerprint --hash-only",
          "agent-sim explore",
          "agent-sim journal log --path \(journalPath) --index \(actionIndex) --action tap --target \"\(target.name)\" --coords \"\(target.tapX),\(target.tapY)\" --before \"\(String(currentFingerprint.prefix(8)))\" --before-name \"\(analysis.screenName)\" --result <navigated|same-screen> --after <new-fingerprint> --after-name <new-screen-name>",
          "agent-sim next --journal \(journalPath)"
        ],
        guardrails: Self.standardGuardrails
      )
    } else {
      // Screen exhausted — navigate back
      let backAction = findBackAction(analysis)
      let actionIndex = journalState.totalActions + 1

      if let back = backAction {
        return NextInstruction(
          phase: .screenExhausted,
          instruction: "All elements tapped on \"\(analysis.screenName)\". Navigate back to parent screen.",
          action: back,
          currentScreen: screenSnapshot,
          progress: progress,
          afterAction: [
            "sleep 1",
            "agent-sim fingerprint --hash-only",
            "agent-sim journal log --path \(journalPath) --index \(actionIndex) --action back --target \"Back navigation\" --before \"\(String(currentFingerprint.prefix(8)))\" --before-name \"\(analysis.screenName)\" --result <navigated|same-screen> --after <fingerprint> --after-name <screen-name>",
            "agent-sim next --journal \(journalPath)"
          ],
          guardrails: Self.standardGuardrails
        )
      } else {
        // Check if there are unselected tabs
        let unselectedTabs = analysis.tabs.filter { !$0.isSelected }
        if let nextTab = unselectedTabs.first {
          return NextInstruction(
            phase: .screenExhausted,
            instruction: "Screen exhausted and no back navigation found. Switch to next tab: \"\(nextTab.label)\".",
            action: .init(
              type: "tap",
              target: nextTab.label,
              command: "agent-sim tap \(nextTab.tapX) \(nextTab.tapY)",
              reason: "Switch to unvisited tab",
              tapX: nextTab.tapX,
              tapY: nextTab.tapY
            ),
            currentScreen: screenSnapshot,
            progress: progress,
            afterAction: [
              "sleep 1",
              "agent-sim explore",
              "agent-sim journal log --path \(journalPath) --index \(actionIndex) --action tap-tab --target \"\(nextTab.label)\" --before \"\(String(currentFingerprint.prefix(8)))\" --before-name \"\(analysis.screenName)\" --result navigated --after <fingerprint> --after-name <screen-name>",
              "agent-sim next --journal \(journalPath)"
            ],
            guardrails: Self.standardGuardrails
          )
        }

        // Nothing left to do
        return completeInstruction(
          reason: "All reachable elements and tabs exhausted.",
          journalState: journalState,
          journalPath: journalPath
        )
      }
    }
  }

  // MARK: - Back Navigation

  private func findBackAction(_ analysis: ScreenAnalysis) -> NextInstruction.SuggestedNextAction? {
    // Priority 1: Back button in navigation area
    if let back = analysis.navigation.first(where: {
      $0.name.lowercased().contains("back")
    }) {
      return .init(
        type: "tap",
        target: back.name,
        command: "agent-sim tap --label \"\(back.name)\"",
        reason: "Back button found in navigation bar",
        tapX: back.tapX,
        tapY: back.tapY
      )
    }

    // Priority 2: Close/Done/Cancel button
    if let dismiss = analysis.navigation.first(where: {
      let name = $0.name.lowercased()
      return name.contains("close") || name.contains("done") || name.contains("cancel")
        || name.contains("dismiss")
    }) {
      return .init(
        type: "tap",
        target: dismiss.name,
        command: "agent-sim tap --label \"\(dismiss.name)\"",
        reason: "Dismiss button found",
        tapX: dismiss.tapX,
        tapY: dismiss.tapY
      )
    }

    // Priority 3: Swipe from left edge
    return .init(
      type: "swipe",
      target: "left-edge",
      command: "agent-sim swipe right --delta 200",
      reason: "No back/close button found — try swipe-from-left-edge gesture",
      tapX: nil,
      tapY: nil
    )
  }

  // MARK: - Phase Constructors

  private func notStartedInstruction() -> NextInstruction {
    let defaultPath = "build/agent-sim/sweep-journal-\(DateFormatter.fileDate.string(from: Date())).md"
    return NextInstruction(
      phase: .notStarted,
      instruction: "No journal found. Initialize a sweep journal and start exploring.",
      action: .init(
        type: "journal-init",
        target: "sweep journal",
        command: "agent-sim journal init --path \(defaultPath) --simulator \"iPhone 16\" --scope \"Full app exploration\"",
        reason: "A journal must exist before the sweep can begin",
        tapX: nil, tapY: nil
      ),
      currentScreen: nil,
      progress: .init(screensVisited: 0, totalActions: 0, issuesFound: 0, crashesDetected: 0, journalPath: nil),
      afterAction: [
        "agent-sim launch \(bundleID ?? "<bundleId>")",
        "sleep 2",
        "agent-sim explore --pretty",
        "agent-sim next --journal \(defaultPath)"
      ],
      guardrails: Self.initGuardrails
    )
  }

  private func crashedInstruction(
    reason: String, recovery: String,
    journalState: SweepStateReader.JournalState, journalPath: String
  ) -> NextInstruction {
    NextInstruction(
      phase: .crashed,
      instruction: "App appears to have crashed: \(reason)",
      action: .init(
        type: "recover",
        target: "app",
        command: recovery,
        reason: reason,
        tapX: nil, tapY: nil
      ),
      currentScreen: nil,
      progress: .init(
        screensVisited: journalState.screens.count,
        totalActions: journalState.totalActions,
        issuesFound: journalState.issues,
        crashesDetected: journalState.crashes + 1,
        journalPath: journalPath
      ),
      afterAction: [
        "sleep 2",
        "agent-sim explore --pretty",
        "agent-sim journal log --path \(journalPath) --index \(journalState.totalActions + 1) --action crash-recovery --target \"App recovery\" --result <navigated|error> --issue \"App crashed: \(reason)\"",
        "agent-sim next --journal \(journalPath)"
      ],
      guardrails: Self.crashGuardrails
    )
  }

  private func completeInstruction(
    reason: String,
    journalState: SweepStateReader.JournalState, journalPath: String
  ) -> NextInstruction {
    NextInstruction(
      phase: .complete,
      instruction: "Sweep complete: \(reason)",
      action: nil,
      currentScreen: nil,
      progress: .init(
        screensVisited: journalState.screens.count,
        totalActions: journalState.totalActions,
        issuesFound: journalState.issues,
        crashesDetected: journalState.crashes,
        journalPath: journalPath
      ),
      afterAction: [
        "agent-sim journal summary --path \(journalPath)"
      ],
      guardrails: [
        "Review the journal for any issues that need follow-up.",
        "Do NOT continue tapping — the sweep is done.",
      ]
    )
  }

  // MARK: - Guardrails

  private static let standardGuardrails = [
    "Always run `agent-sim fingerprint` AFTER tapping to detect screen transitions.",
    "If fingerprint changed → new screen. Run `agent-sim explore` to classify it.",
    "If fingerprint is the same → element stayed on same screen. Move to next element.",
    "Journal EVERY action immediately — do not batch.",
    "SKIP destructive elements (Delete, Sign Out, Remove) unless explicitly told to test them.",
    "If the screen shows a loading spinner, wait 2 seconds and retry explore.",
    "If tap fails but isn't a crash (element disappeared), note it in the journal and continue.",
    "Do NOT type into text fields during exploration — focus on tap interactions.",
  ]

  private static let initGuardrails = [
    "Create the journal BEFORE launching the app.",
    "Wait at least 2 seconds after launch before first explore.",
    "Confirm the app is on the expected entry screen before starting the sweep.",
  ]

  private static let crashGuardrails = [
    "Log the crash in the journal with the action that triggered it.",
    "Take a screenshot before recovering: `agent-sim screenshot`.",
    "After recovery, verify the app is back to a known screen with `agent-sim explore`.",
    "Do NOT retry the same action that caused the crash.",
  ]

  // MARK: - Output

  private func printPretty(_ instruction: NextInstruction) {
    print("Phase: \(instruction.phase.rawValue)")
    print("Instruction: \(instruction.instruction)")
    print("")

    if let action = instruction.action {
      print("Next action:")
      print("  Type: \(action.type)")
      print("  Target: \(action.target)")
      print("  Command: \(action.command)")
      print("  Reason: \(action.reason)")
      if let x = action.tapX, let y = action.tapY {
        print("  Coordinates: (\(x), \(y))")
      }
      print("")
    }

    if let screen = instruction.currentScreen {
      print("Current screen: \(screen.name)")
      print("  Fingerprint: \(screen.fingerprint)")
      print("  Interactive: \(screen.interactiveCount) (\(screen.tappedCount) tapped, \(screen.remainingCount) remaining)")
      print("")
    }

    let p = instruction.progress
    print("Progress: \(p.screensVisited) screens, \(p.totalActions) actions, \(p.issuesFound) issues, \(p.crashesDetected) crashes")

    if !instruction.afterAction.isEmpty {
      print("")
      print("After this action, run:")
      for (i, step) in instruction.afterAction.enumerated() {
        print("  \(i + 1). \(step)")
      }
    }

    if !instruction.guardrails.isEmpty {
      print("")
      print("Guardrails:")
      for rail in instruction.guardrails {
        print("  - \(rail)")
      }
    }
  }

  private func printJSON(_ value: some Encodable) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(value) {
      print(String(data: data, encoding: .utf8) ?? "{}")
    }
  }
}

private extension DateFormatter {
  static let fileDate: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd-HHmmss"
    return f
  }()
}
