import Testing
@testable import AgentSimLib

@Suite("SweepStateReader — journal markdown parsing")
struct SweepStateReaderTests {

  @Test("Returns nil for nonexistent journal path")
  func nonexistentFile() {
    let state = SweepStateReader.readJournal(at: "/nonexistent/path.md")
    #expect(state == nil)
  }

  @Test("Empty journal (header only) returns zero counts")
  func emptyJournal() {
    let path = JournalFixtures.writeTempFile(JournalFixtures.empty)
    let state = SweepStateReader.readJournal(at: path)

    #expect(state != nil)
    #expect(state?.totalActions == 0)
    #expect(state?.navigations == 0)
    #expect(state?.sameScreen == 0)
    #expect(state?.crashes == 0)
    #expect(state?.issues == 0)
    #expect(state?.screens.isEmpty == true)
    #expect(state?.tappedElements.isEmpty == true)
  }

  @Test("Parses action count from ### headings")
  func countsActions() {
    let path = JournalFixtures.writeTempFile(JournalFixtures.threeActions)
    let state = SweepStateReader.readJournal(at: path)!

    #expect(state.totalActions == 3)
  }

  @Test("Counts navigated results")
  func countsNavigated() {
    let path = JournalFixtures.writeTempFile(JournalFixtures.threeActions)
    let state = SweepStateReader.readJournal(at: path)!

    #expect(state.navigations == 3) // all three actions navigated
  }

  @Test("Counts same-screen results")
  func countsSameScreen() {
    let path = JournalFixtures.writeTempFile(JournalFixtures.sameScreenOnly)
    let state = SweepStateReader.readJournal(at: path)!

    #expect(state.sameScreen == 2)
    #expect(state.navigations == 0)
  }

  @Test("Counts crash results")
  func countsCrashes() {
    let path = JournalFixtures.writeTempFile(JournalFixtures.withIssuesAndCrash)
    let state = SweepStateReader.readJournal(at: path)!

    #expect(state.crashes == 1)
  }

  @Test("Counts issues from Issue lines")
  func countsIssues() {
    let path = JournalFixtures.writeTempFile(JournalFixtures.withIssuesAndCrash)
    let state = SweepStateReader.readJournal(at: path)!

    #expect(state.issues == 2) // "does not navigate" + "crashed"
  }

  @Test("Extracts unique screen fingerprints")
  func extractsScreens() {
    let path = JournalFixtures.writeTempFile(JournalFixtures.threeActions)
    let state = SweepStateReader.readJournal(at: path)!

    // Should have: abc12345, def67890, ghi11111
    #expect(state.screens.count == 3)
    #expect(state.screens.contains("abc12345"))
    #expect(state.screens.contains("def67890"))
    #expect(state.screens.contains("ghi11111"))
  }

  @Test("Tracks tapped elements as fingerprint:target pairs")
  func tracksTappedElements() {
    let path = JournalFixtures.writeTempFile(JournalFixtures.threeActions)
    let state = SweepStateReader.readJournal(at: path)!

    // Action 1: tapped "Sign In" on screen abc12345
    #expect(state.tappedElements.contains("abc12345:Sign In"))
    // Action 2: tapped "View Profile" on screen def67890
    #expect(state.tappedElements.contains("def67890:View Profile"))
  }

  @Test("Tracks last fingerprint and screen name")
  func tracksLastScreen() {
    let path = JournalFixtures.writeTempFile(JournalFixtures.threeActions)
    let state = SweepStateReader.readJournal(at: path)!

    #expect(state.lastFingerprint == "def67890")
    #expect(state.lastScreenName == "Home")
  }

  @Test("Deduplicates screen fingerprints")
  func deduplicatesScreens() {
    let path = JournalFixtures.writeTempFile(JournalFixtures.sameScreenOnly)
    let state = SweepStateReader.readJournal(at: path)!

    // Same screen visited twice → only 1 unique screen
    #expect(state.screens.count == 1)
    #expect(state.screens.contains("aaa11111"))
  }

  // MARK: - JSON Sidecar

  @Test("JSON sidecar exists → reads from JSON, not markdown")
  func jsonSidecarPreferred() {
    // Write markdown with threeActions content
    let path = JournalFixtures.writeTempFile(JournalFixtures.threeActions)
    // Write JSON sidecar with only 2 entries (different from markdown)
    let twoEntries = Array(JournalFixtures.sampleEntries().prefix(2))
    JournalFixtures.writeJSONSidecar(for: path, entries: twoEntries)

    let state = SweepStateReader.readJournal(at: path)!

    // Should read from JSON (2 actions), not markdown (3 actions)
    #expect(state.totalActions == 2)
  }

  @Test("No JSON sidecar → falls back to markdown")
  func noJsonFallsBackToMarkdown() {
    let path = JournalFixtures.writeTempFile(JournalFixtures.threeActions)
    // No JSON sidecar written — should parse markdown
    let state = SweepStateReader.readJournal(at: path)!

    #expect(state.totalActions == 3)
    #expect(state.navigations == 3)
  }

  @Test("JSON sidecar computes correct JournalState")
  func jsonSidecarComputesState() {
    let path = JournalFixtures.writeTempFile(JournalFixtures.empty)
    JournalFixtures.writeJSONSidecar(for: path, entries: JournalFixtures.sampleEntries())

    let state = SweepStateReader.readJournal(at: path)!

    #expect(state.totalActions == 3)
    #expect(state.navigations == 3)
    #expect(state.screens.count == 3)
    #expect(state.screens.contains("abc12345"))
    #expect(state.screens.contains("def67890"))
    #expect(state.screens.contains("ghi11111"))
    #expect(state.tappedElements.contains("abc12345:Sign In"))
    #expect(state.tappedElements.contains("def67890:View Profile"))
    #expect(state.lastFingerprint == "def67890")
    #expect(state.lastScreenName == "Home")
  }

  // MARK: - Depth Tracking

  @Test("Depth tracked from markdown — forward navigations increase depth")
  func depthFromMarkdownForward() {
    let path = JournalFixtures.writeTempFile(JournalFixtures.threeActions)
    let state = SweepStateReader.readJournal(at: path)!

    // Action 1: tap → navigated (depth 1)
    // Action 2: tap → navigated (depth 2)
    // Action 3: back → navigated (depth 1)
    #expect(state.currentDepth == 1)
  }

  @Test("Depth resets to 0 on crash")
  func depthResetsOnCrash() {
    let path = JournalFixtures.writeTempFile(JournalFixtures.withIssuesAndCrash)
    let state = SweepStateReader.readJournal(at: path)!

    // Action 1: tap → navigated (depth 1)
    // Action 2: tap → same-screen (depth 1)
    // Action 3: tap → crash (depth 0)
    // Action 4: crash-recovery → navigated (depth 1)
    #expect(state.currentDepth == 1)
  }

  // MARK: - Tapped Element Edge Cases

  @Test("Entry with empty target is not added to tappedElements")
  func emptyTargetNotTapped() {
    let entries = [
      JournalEntry(
        index: 1, action: "tap", target: "",
        coords: nil, screenBefore: "abc12345", screenBeforeName: "Home",
        result: "same-screen", screenAfter: nil, screenAfterName: nil,
        screenshot: nil, issue: nil, timestamp: "2026-02-22T10:00:00Z"
      ),
    ]
    let state = SweepStateReader.computeStateFromEntries(entries)

    #expect(state.tappedElements.isEmpty)
  }

  @Test("Entry with empty screenBefore is not added to tappedElements")
  func emptyScreenBeforeNotTapped() {
    let entries = [
      JournalEntry(
        index: 1, action: "tap", target: "Button",
        coords: nil, screenBefore: "", screenBeforeName: "",
        result: "same-screen", screenAfter: nil, screenAfterName: nil,
        screenshot: nil, issue: nil, timestamp: "2026-02-22T10:00:00Z"
      ),
    ]
    let state = SweepStateReader.computeStateFromEntries(entries)

    #expect(state.tappedElements.isEmpty)
  }

  @Test("Entries without issues have zero issue count")
  func noIssuesCountsZero() {
    let entries = [
      JournalEntry(
        index: 1, action: "tap", target: "A",
        coords: nil, screenBefore: "s1", screenBeforeName: "S1",
        result: "same-screen", screenAfter: nil, screenAfterName: nil,
        screenshot: nil, issue: nil, timestamp: "2026-02-22T10:00:00Z"
      ),
    ]
    let state = SweepStateReader.computeStateFromEntries(entries)

    #expect(state.issues == 0)
  }

  @Test("Entries with issues count correctly")
  func issuesCounted() {
    let entries = [
      JournalEntry(
        index: 1, action: "tap", target: "A",
        coords: nil, screenBefore: "s1", screenBeforeName: "S1",
        result: "same-screen", screenAfter: nil, screenAfterName: nil,
        screenshot: nil, issue: "Button does nothing", timestamp: "2026-02-22T10:00:00Z"
      ),
      JournalEntry(
        index: 2, action: "tap", target: "B",
        coords: nil, screenBefore: "s1", screenBeforeName: "S1",
        result: "navigated", screenAfter: "s2", screenAfterName: "S2",
        screenshot: nil, issue: nil, timestamp: "2026-02-22T10:01:00Z"
      ),
    ]
    let state = SweepStateReader.computeStateFromEntries(entries)

    #expect(state.issues == 1)
  }

  @Test("Forward-only navigation depth increments correctly")
  func forwardOnlyDepth() {
    let entries = [
      JournalEntry(
        index: 1, action: "tap", target: "A",
        coords: nil, screenBefore: "s1", screenBeforeName: "S1",
        result: "navigated", screenAfter: "s2", screenAfterName: "S2",
        screenshot: nil, issue: nil, timestamp: "2026-02-22T10:00:00Z"
      ),
      JournalEntry(
        index: 2, action: "tap", target: "B",
        coords: nil, screenBefore: "s2", screenBeforeName: "S2",
        result: "navigated", screenAfter: "s3", screenAfterName: "S3",
        screenshot: nil, issue: nil, timestamp: "2026-02-22T10:01:00Z"
      ),
      JournalEntry(
        index: 3, action: "tap", target: "C",
        coords: nil, screenBefore: "s3", screenBeforeName: "S3",
        result: "navigated", screenAfter: "s4", screenAfterName: "S4",
        screenshot: nil, issue: nil, timestamp: "2026-02-22T10:02:00Z"
      ),
    ]
    let state = SweepStateReader.computeStateFromEntries(entries)

    #expect(state.currentDepth == 3)
  }

  // MARK: - Markdown Depth Edge Cases

  @Test("Markdown forward-only navigations produce correct depth")
  func markdownForwardOnlyDepth() {
    let path = JournalFixtures.writeTempFile(JournalFixtures.forwardOnly)
    let state = SweepStateReader.readJournal(at: path)!

    // 3 forward taps → depth 3
    #expect(state.currentDepth == 3)
  }

  @Test("Markdown extractFingerprint returns nil for malformed lines")
  func markdownMalformedScreenLine() {
    let markdown = """
      # Sweep Journal

      ## Actions

      ### #1 — Sign In

      - **Action**: tap
      - **Screen before**:
      - **Result**: same-screen

      """
    let path = JournalFixtures.writeTempFile(markdown)
    let state = SweepStateReader.readJournal(at: path)!

    #expect(state.screens.isEmpty)
  }
}
