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
      JSONOutput.print(instruction)
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
      return Self.determineInstruction(
        journalPath: journalPath, journalState: journalState,
        analysis: nil, simulatorError: "\(error)",
        bundleID: bundleID, maxScreens: maxScreens,
        maxDepth: maxDepth
      )
    }

    let simNode: AXNode
    do {
      simNode = try await AXTreeReader.readDeviceTree(simulatorUDID: device.udid)
    } catch {
      return Self.determineInstruction(
        journalPath: journalPath, journalState: journalState,
        analysis: nil, simulatorError: nil,
        bundleID: bundleID, maxScreens: maxScreens,
        maxDepth: maxDepth
      )
    }
    let analysis = ScreenAnalyzer.analyze(simNode)

    return Self.determineInstruction(
      journalPath: journalPath, journalState: journalState,
      analysis: analysis, simulatorError: nil,
      bundleID: bundleID, maxScreens: maxScreens,
      maxDepth: maxDepth
    )
  }

  // MARK: - Pure State Machine (static, testable)

  static func determineInstruction(
    journalPath: String,
    journalState: SweepStateReader.JournalState,
    analysis: ScreenAnalysis?,
    simulatorError: String?,
    bundleID: String?,
    maxScreens: Int,
    maxDepth: Int = 80
  ) -> NextInstruction {
    // Simulator error → crashed
    if let error = simulatorError {
      return crashedInstruction(
        reason: error,
        recovery: "agent-sim use \"<device name>\"",
        journalState: journalState,
        journalPath: journalPath,
        bundleID: bundleID
      )
    }

    // No AX tree → crashed (app not running)
    guard let analysis else {
      return crashedInstruction(
        reason: "No app content found — app may have crashed or is on SpringBoard.",
        recovery: "agent-sim launch \(bundleID ?? "<bundleId>")",
        journalState: journalState,
        journalPath: journalPath,
        bundleID: bundleID
      )
    }

    // System UI overlay → recovery via screenshot + coordinate tap
    if let warning = analysis.warning {
      return NextInstruction(
        phase: .screenExhausted,
        instruction: warning,
        action: .init(
          type: .recover,
          target: "system-ui-overlay",
          command: "agent-sim screenshot",
          reason: "System dialog is blocking the app — the AX tree cannot see it. "
            + "Take a screenshot, identify button positions visually, then use coordinate-based tap.",
          tapX: nil, tapY: nil
        ),
        currentScreen: .init(
          name: analysis.screenName,
          fingerprint: analysis.fingerprint,
          interactiveCount: analysis.interactiveCount,
          tappedCount: 0,
          remainingCount: 0
        ),
        progress: .init(
          screensVisited: journalState.screens.count,
          totalActions: journalState.totalActions,
          issuesFound: journalState.issues,
          crashesDetected: journalState.crashes,
          journalPath: journalPath
        ),
        afterAction: [
          "# Look at the screenshot to identify the dialog buttons",
          "agent-sim tap <x> <y>  # tap the appropriate button (e.g. Allow, Continue, Cancel)",
          "agent-sim wait --timeout 5",
          "agent-sim next --journal \(shellEscape(journalPath))"
        ],
        guardrails: [
          "System dialogs (Apple Sign In, permission prompts, biometrics) are INVISIBLE to the AX tree.",
          "You MUST use `agent-sim screenshot` to see what's on screen.",
          "Use coordinate-based `agent-sim tap <x> <y>` — label-based tap will NOT work.",
          "Common patterns: 'Allow' is usually bottom-right, 'Don't Allow' is bottom-left.",
          "After dismissing, run `agent-sim explore` to verify the app is back to normal.",
        ]
      )
    }

    // Check limits
    if journalState.screens.count >= maxScreens {
      return completeInstruction(
        reason: "Reached screen limit (\(maxScreens)).",
        journalState: journalState,
        journalPath: journalPath
      )
    }

    // Determine what to do on this screen
    let currentFingerprint = analysis.fingerprint
    let shortFP = Fingerprinter.shortFingerprint(from: currentFingerprint)
    let isNewScreen = !journalState.screens.contains(shortFP)

    // Find untapped elements
    let untapped = analysis.actions.filter { action in
      let key = "\(Fingerprinter.shortFingerprint(from: currentFingerprint)):\(action.name)"
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

    let actionIndex = journalState.totalActions + 1

    // Helper: build afterAction with --auto-after (agent copies, never assembles)
    func afterActionForTap(action: String, target: String, coords: String) -> [String] {
      [
        "agent-sim wait --timeout 5",
        "agent-sim journal log --path \(shellEscape(journalPath)) --index \(actionIndex) --action \(shellEscape(action)) --target \(shellEscape(target)) --coords \(shellEscape(coords)) --before \(shellEscape(shortFP)) --before-name \(shellEscape(analysis.screenName)) --auto-after",
        "agent-sim next --journal \(shellEscape(journalPath))"
      ]
    }

    func afterActionForBack(target: String) -> [String] {
      [
        "agent-sim wait --timeout 5",
        "agent-sim journal log --path \(shellEscape(journalPath)) --index \(actionIndex) --action back --target \(shellEscape(target)) --before \(shellEscape(shortFP)) --before-name \(shellEscape(analysis.screenName)) --auto-after",
        "agent-sim next --journal \(shellEscape(journalPath))"
      ]
    }

    // Depth limit: only block forward navigation on new screens
    if isNewScreen && journalState.currentDepth >= maxDepth {
      return NextInstruction(
        phase: .screenExhausted,
        instruction: "Maximum depth reached (\(maxDepth)). Navigate back to parent screen.",
        action: findBackAction(analysis),
        currentScreen: screenSnapshot,
        progress: progress,
        afterAction: afterActionForBack(target: "Back navigation"),
        guardrails: standardGuardrails
      )
    }

    // Decide phase and action
    if isNewScreen && !untapped.isEmpty {
      // New screen with elements to tap
      let target = untapped[0]

      return NextInstruction(
        phase: .newScreen,
        instruction: "New screen discovered: \"\(analysis.screenName)\". Tap the first untapped element.",
        action: .init(
          type: .tap,
          target: target.name,
          command: "agent-sim tap --label \(shellEscape(target.name))",
          reason: "First untapped interactive element on new screen",
          tapX: target.tapX,
          tapY: target.tapY
        ),
        currentScreen: screenSnapshot,
        progress: progress,
        afterAction: afterActionForTap(action: "tap", target: target.name, coords: "\(target.tapX),\(target.tapY)"),
        guardrails: standardGuardrails
      )
    } else if !untapped.isEmpty {
      // Known screen with untapped elements
      let target = untapped[0]

      return NextInstruction(
        phase: .exploring,
        instruction: "Continue exploring \"\(analysis.screenName)\". \(untapped.count) elements remaining.",
        action: .init(
          type: .tap,
          target: target.name,
          command: "agent-sim tap --label \(shellEscape(target.name))",
          reason: "\(untapped.count) untapped elements remain on this screen",
          tapX: target.tapX,
          tapY: target.tapY
        ),
        currentScreen: screenSnapshot,
        progress: progress,
        afterAction: afterActionForTap(action: "tap", target: target.name, coords: "\(target.tapX),\(target.tapY)"),
        guardrails: standardGuardrails
      )
    } else {
      // Screen exhausted — navigate back
      let backAction = findBackAction(analysis)

      if let back = backAction {
        return NextInstruction(
          phase: .screenExhausted,
          instruction: "All elements tapped on \"\(analysis.screenName)\". Navigate back to parent screen.",
          action: back,
          currentScreen: screenSnapshot,
          progress: progress,
          afterAction: afterActionForBack(target: back.target),
          guardrails: standardGuardrails
        )
      } else {
        // Check if there are unselected tabs
        let unselectedTabs = analysis.tabs.filter { !$0.isSelected }
        if let nextTab = unselectedTabs.first {
          return NextInstruction(
            phase: .screenExhausted,
            instruction: "Screen exhausted and no back navigation found. Switch to next tab: \"\(nextTab.label)\".",
            action: .init(
              type: .tap,
              target: nextTab.label,
              command: "agent-sim tap \(nextTab.tapX) \(nextTab.tapY)",
              reason: "Switch to unvisited tab",
              tapX: nextTab.tapX,
              tapY: nextTab.tapY
            ),
            currentScreen: screenSnapshot,
            progress: progress,
            afterAction: afterActionForTap(action: "tap-tab", target: nextTab.label, coords: "\(nextTab.tapX),\(nextTab.tapY)"),
            guardrails: standardGuardrails
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

  static func findBackAction(_ analysis: ScreenAnalysis) -> NextInstruction.SuggestedNextAction? {
    // Priority 1: Back button in navigation area
    if let back = analysis.navigation.first(where: {
      $0.name.lowercased().contains("back")
    }) {
      return .init(
        type: .tap,
        target: back.name,
        command: "agent-sim tap --label \(shellEscape(back.name))",
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
        type: .tap,
        target: dismiss.name,
        command: "agent-sim tap --label \(shellEscape(dismiss.name))",
        reason: "Dismiss button found",
        tapX: dismiss.tapX,
        tapY: dismiss.tapY
      )
    }

    // Priority 3: Swipe from left edge
    return .init(
      type: .swipe,
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
        type: .journalInit,
        target: "sweep journal",
        command: "agent-sim journal init --path \(shellEscape(defaultPath)) --simulator 'iPhone 16' --scope 'Full app exploration'",
        reason: "A journal must exist before the sweep can begin",
        tapX: nil, tapY: nil
      ),
      currentScreen: nil,
      progress: .init(screensVisited: 0, totalActions: 0, issuesFound: 0, crashesDetected: 0, journalPath: nil),
      afterAction: [
        "agent-sim boot",
        "agent-sim launch \(shellEscape(bundleID ?? "<bundleId>"))",
        "agent-sim wait --timeout 10",
        "agent-sim explore --pretty",
        "agent-sim next --journal \(shellEscape(defaultPath))"
      ],
      guardrails: Self.initGuardrails
    )
  }

  private static func crashedInstruction(
    reason: String, recovery: String,
    journalState: SweepStateReader.JournalState, journalPath: String,
    bundleID: String?
  ) -> NextInstruction {
    NextInstruction(
      phase: .crashed,
      instruction: "App appears to have crashed: \(reason)",
      action: .init(
        type: .recover,
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
        "agent-sim wait --timeout 10",
        "agent-sim journal log --path \(shellEscape(journalPath)) --index \(journalState.totalActions + 1) --action crash-recovery --target 'App recovery' --auto-after --issue \(shellEscape("App crashed: \(reason)"))",
        "agent-sim next --journal \(shellEscape(journalPath))"
      ],
      guardrails: crashGuardrails
    )
  }

  private static func completeInstruction(
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
        "agent-sim journal summary --path \(shellEscape(journalPath))"
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
    "Use `agent-sim wait` after launch — it blocks until the screen is ready.",
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

}

private extension DateFormatter {
  static let fileDate: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd-HHmmss"
    return f
  }()
}
