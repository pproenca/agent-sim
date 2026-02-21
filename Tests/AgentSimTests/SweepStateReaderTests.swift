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
}
