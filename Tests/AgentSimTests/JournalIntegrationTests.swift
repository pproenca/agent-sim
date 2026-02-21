import Testing
import Foundation
@testable import AgentSimLib

@Suite("Journal — file operations round-trip")
struct JournalIntegrationTests {

  @Test("SweepStateReader parses multi-action journal correctly")
  func multiActionJournal() {
    let path = JournalFixtures.writeTempFile(JournalFixtures.threeActions)
    let state = SweepStateReader.readJournal(at: path)!

    #expect(state.totalActions == 3)
    #expect(state.navigations == 3)
    #expect(state.sameScreen == 0)
    #expect(state.crashes == 0)
    #expect(state.issues == 0)
    #expect(state.screens.count == 3) // abc12345, def67890, ghi11111
  }

  @Test("SweepStateReader parses journal with issues and crash")
  func issuesAndCrash() {
    let path = JournalFixtures.writeTempFile(JournalFixtures.withIssuesAndCrash)
    let state = SweepStateReader.readJournal(at: path)!

    #expect(state.totalActions == 4)
    #expect(state.navigations == 2) // #1 navigated, #4 navigated
    #expect(state.sameScreen == 1) // #2 same-screen
    #expect(state.crashes == 1) // #3 crash
    #expect(state.issues == 2) // #2 and #3 have issues
  }

  @Test("SweepStateReader correctly identifies tapped elements for 'already visited' checks")
  func alreadyVisitedCheck() {
    let path = JournalFixtures.writeTempFile(JournalFixtures.threeActions)
    let state = SweepStateReader.readJournal(at: path)!

    // "Sign In" was tapped on screen abc12345
    #expect(state.tappedElements.contains("abc12345:Sign In"))
    // "View Profile" was tapped on screen def67890
    #expect(state.tappedElements.contains("def67890:View Profile"))
    // "Back" was tapped on screen ghi11111
    #expect(state.tappedElements.contains("ghi11111:Back"))

    // "Sign In" was NOT tapped on screen def67890
    #expect(!state.tappedElements.contains("def67890:Sign In"))
  }

  @Test("SweepStateReader handles journal where all actions stay on same screen")
  func allSameScreen() {
    let path = JournalFixtures.writeTempFile(JournalFixtures.sameScreenOnly)
    let state = SweepStateReader.readJournal(at: path)!

    #expect(state.totalActions == 2)
    #expect(state.sameScreen == 2)
    #expect(state.navigations == 0)
    #expect(state.screens.count == 1)
    #expect(state.lastFingerprint == "aaa11111")
    #expect(state.lastScreenName == "Settings")
  }
}
