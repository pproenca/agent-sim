import Testing
@testable import AgentSimLib

@Suite("Next.determineInstruction — state machine transitions")
struct NextInstructionTests {

  // MARK: - Helpers

  private func emptyJournalState() -> SweepStateReader.JournalState {
    SweepStateReader.JournalState(
      totalActions: 0, navigations: 0, sameScreen: 0,
      crashes: 0, issues: 0,
      screens: [], tappedElements: [],
      lastFingerprint: nil, lastScreenName: nil
    )
  }

  private func journalState(
    totalActions: Int = 0,
    screens: Set<String> = [],
    tappedElements: Set<String> = [],
    crashes: Int = 0,
    issues: Int = 0
  ) -> SweepStateReader.JournalState {
    SweepStateReader.JournalState(
      totalActions: totalActions, navigations: 0, sameScreen: 0,
      crashes: crashes, issues: issues,
      screens: screens, tappedElements: tappedElements,
      lastFingerprint: nil, lastScreenName: nil
    )
  }

  private func analysisWithActions(_ labels: [String], screenName: String = "Test Screen") -> ScreenAnalysis {
    let buttons = labels.map { AXNodeBuilder.button($0, at: (196, 400)) }
    let title = AXNodeBuilder.text(screenName, at: (0, 60), size: (393, 30))
    let tree = AXNodeBuilder.screenContent(children: [title] + buttons)
    return ScreenAnalyzer.analyze(tree)
  }

  private func analysisWithBackButton(screenName: String = "Detail Screen") -> ScreenAnalysis {
    let back = AXNodeBuilder.button("Back", at: (30, 50))
    let title = AXNodeBuilder.text(screenName, at: (100, 60), size: (200, 30))
    let tree = AXNodeBuilder.screenContent(children: [back, title])
    return ScreenAnalyzer.analyze(tree)
  }

  private func analysisWithTabs(
    tabs: [(String, Bool)],
    actions: [String] = [],
    screenName: String = "Tab Screen"
  ) -> ScreenAnalysis {
    let tabGroup = AXNodeBuilder.tabGroup(tabs: tabs)
    let title = AXNodeBuilder.text(screenName, at: (0, 60), size: (393, 30))
    let buttons = actions.map { AXNodeBuilder.button($0, at: (196, 400)) }
    let tree = AXNodeBuilder.screenContent(children: [title, tabGroup] + buttons)
    return ScreenAnalyzer.analyze(tree)
  }

  // MARK: - Simulator Error → .crashed

  @Test("Simulator error produces crashed phase")
  func simulatorErrorCrashed() {
    let result = Next.determineInstruction(
      journalPath: "/tmp/journal.md",
      journalState: emptyJournalState(),
      analysis: nil,
      simulatorError: "No booted iOS Simulator found.",
      bundleID: "com.test.app",
      maxScreens: 80
    )

    #expect(result.phase == .crashed)
    #expect(result.action?.type == .recover)
    #expect(result.progress.crashesDetected == 1)
  }

  // MARK: - No AX Tree → .crashed (app not running)

  @Test("No AX tree produces crashed phase with launch recovery")
  func noAXTreeCrashed() {
    let result = Next.determineInstruction(
      journalPath: "/tmp/journal.md",
      journalState: emptyJournalState(),
      analysis: nil,
      simulatorError: nil,
      bundleID: "com.test.app",
      maxScreens: 80
    )

    #expect(result.phase == .crashed)
    #expect(result.action?.command.contains("launch") == true)
  }

  // MARK: - Screen Limit → .complete

  @Test("Screen limit reached produces complete phase")
  func screenLimitComplete() {
    let screens = Set((0..<80).map { "screen\($0)" })
    let state = journalState(totalActions: 200, screens: screens)
    let analysis = analysisWithActions(["Button A"])

    let result = Next.determineInstruction(
      journalPath: "/tmp/journal.md",
      journalState: state,
      analysis: analysis,
      simulatorError: nil,
      bundleID: nil,
      maxScreens: 80
    )

    #expect(result.phase == .complete)
    #expect(result.action == nil)
  }

  // MARK: - New Screen + Untapped Elements → .newScreen

  @Test("New screen with untapped elements produces newScreen phase")
  func newScreenWithElements() {
    let state = emptyJournalState()
    let analysis = analysisWithActions(["Sign In", "Register"])

    let result = Next.determineInstruction(
      journalPath: "/tmp/journal.md",
      journalState: state,
      analysis: analysis,
      simulatorError: nil,
      bundleID: nil,
      maxScreens: 80
    )

    #expect(result.phase == .newScreen)
    #expect(result.action?.type == .tap)
    #expect(result.action?.target == "Sign In")
    #expect(result.currentScreen?.remainingCount == 2)
  }

  // MARK: - Known Screen + Untapped Elements → .exploring

  @Test("Known screen with untapped elements produces exploring phase")
  func knownScreenExploring() {
    let analysis = analysisWithActions(["Button A", "Button B"])
    let shortFP = Fingerprinter.shortFingerprint(from: analysis.fingerprint)

    // Mark the screen as already seen, but elements not tapped
    let state = journalState(totalActions: 3, screens: [shortFP])

    let result = Next.determineInstruction(
      journalPath: "/tmp/journal.md",
      journalState: state,
      analysis: analysis,
      simulatorError: nil,
      bundleID: nil,
      maxScreens: 80
    )

    #expect(result.phase == .exploring)
    #expect(result.action?.type == .tap)
    #expect(result.currentScreen?.remainingCount == 2)
  }

  // MARK: - Screen Exhausted + Back Button → .screenExhausted (tap back)

  @Test("Exhausted screen with back button navigates back")
  func screenExhaustedTapBack() {
    let analysis = analysisWithBackButton()
    let shortFP = Fingerprinter.shortFingerprint(from: analysis.fingerprint)

    // Mark screen as seen — no tappable actions (back is navigation, not action)
    let state = journalState(totalActions: 5, screens: [shortFP])

    let result = Next.determineInstruction(
      journalPath: "/tmp/journal.md",
      journalState: state,
      analysis: analysis,
      simulatorError: nil,
      bundleID: nil,
      maxScreens: 80
    )

    #expect(result.phase == .screenExhausted)
    #expect(result.action?.target == "Back")
  }

  // MARK: - Screen Exhausted + Untapped Tab Buttons → .exploring (tab buttons are actions)

  @Test("Tab buttons appear as actions — tapping them follows the exploring phase")
  func tabButtonsAreActions() {
    // Tab group children are AXButton, so they appear as interactive actions
    let analysis = analysisWithTabs(
      tabs: [("Home", true), ("Profile", false)],
      actions: []
    )
    let shortFP = Fingerprinter.shortFingerprint(from: analysis.fingerprint)
    let state = journalState(totalActions: 5, screens: [shortFP])

    let result = Next.determineInstruction(
      journalPath: "/tmp/journal.md",
      journalState: state,
      analysis: analysis,
      simulatorError: nil,
      bundleID: nil,
      maxScreens: 80
    )

    // Tab buttons show up as untapped actions → exploring
    #expect(result.phase == .exploring)
  }

  // MARK: - Screen Exhausted (all tapped) → .screenExhausted with swipe fallback

  @Test("All actions tapped and no back button produces screenExhausted with swipe")
  func allTappedSwipeFallback() {
    let analysis = analysisWithActions(["Submit"])
    let shortFP = Fingerprinter.shortFingerprint(from: analysis.fingerprint)

    // Mark all actions as tapped
    let state = journalState(
      totalActions: 10,
      screens: [shortFP],
      tappedElements: ["\(shortFP):Submit"]
    )

    let result = Next.determineInstruction(
      journalPath: "/tmp/journal.md",
      journalState: state,
      analysis: analysis,
      simulatorError: nil,
      bundleID: nil,
      maxScreens: 80
    )

    // findBackAction always returns a swipe fallback when no nav buttons exist
    #expect(result.phase == .screenExhausted)
    #expect(result.action?.type == .swipe)
  }

  // MARK: - Progress tracking

  @Test("Progress reflects journal state")
  func progressTracksJournalState() {
    let state = journalState(totalActions: 15, screens: ["a", "b", "c"], crashes: 2, issues: 5)
    let analysis = analysisWithActions(["Next"])

    let result = Next.determineInstruction(
      journalPath: "/tmp/journal.md",
      journalState: state,
      analysis: analysis,
      simulatorError: nil,
      bundleID: nil,
      maxScreens: 80
    )

    #expect(result.progress.screensVisited == 3)
    #expect(result.progress.totalActions == 15)
    #expect(result.progress.issuesFound == 5)
    #expect(result.progress.crashesDetected == 2)
  }

  // MARK: - Already-tapped elements are skipped

  @Test("Already-tapped elements are excluded from untapped count")
  func alreadyTappedSkipped() {
    let analysis = analysisWithActions(["Button A", "Button B"])
    let shortFP = Fingerprinter.shortFingerprint(from: analysis.fingerprint)

    // Mark "Button A" as already tapped on this screen
    let state = journalState(
      totalActions: 1,
      screens: [shortFP],
      tappedElements: ["\(shortFP):Button A"]
    )

    let result = Next.determineInstruction(
      journalPath: "/tmp/journal.md",
      journalState: state,
      analysis: analysis,
      simulatorError: nil,
      bundleID: nil,
      maxScreens: 80
    )

    #expect(result.phase == .exploring)
    #expect(result.action?.target == "Button B")
    #expect(result.currentScreen?.remainingCount == 1)
    #expect(result.currentScreen?.tappedCount == 1)
  }

  // MARK: - findBackAction

  @Test("findBackAction prioritizes Back button over Close button")
  func findBackPrioritizesBack() {
    let back = AXNodeBuilder.button("Back", at: (30, 50))
    let close = AXNodeBuilder.button("Close", at: (360, 50))
    let tree = AXNodeBuilder.screenContent(children: [back, close])
    let analysis = ScreenAnalyzer.analyze(tree)

    let action = Next.findBackAction(analysis)
    #expect(action?.target == "Back")
  }

  @Test("findBackAction falls back to swipe when no navigation buttons exist")
  func findBackFallsBackToSwipe() {
    let button = AXNodeBuilder.button("Submit", at: (196, 400))
    let tree = AXNodeBuilder.screenContent(children: [button])
    let analysis = ScreenAnalyzer.analyze(tree)

    let action = Next.findBackAction(analysis)
    #expect(action?.type == .swipe)
    #expect(action?.target == "left-edge")
  }
}
