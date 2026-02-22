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

  // MARK: - JournalEntry field values (ternary correctness via production builders)

  @Test("coords field is nil when coords string is empty")
  func coordsNilWhenEmpty() {
    let entry = JournalLog.buildJournalEntry(
      index: 1, action: "tap", target: "Button",
      coords: "", before: "s1", beforeName: "S1",
      result: "same-screen", after: "s2", afterName: "S2",
      screenshot: nil, issue: nil
    )
    #expect(entry.coords == nil)
  }

  @Test("coords field preserves value when non-empty")
  func coordsPreservedWhenPresent() {
    let entry = JournalLog.buildJournalEntry(
      index: 1, action: "tap", target: "Button",
      coords: "196,400", before: "s1", beforeName: "S1",
      result: "same-screen", after: "s2", afterName: "S2",
      screenshot: nil, issue: nil
    )
    #expect(entry.coords == "196,400")
  }

  @Test("screenAfter is nil when after string is empty")
  func screenAfterNilWhenEmpty() {
    let entry = JournalLog.buildJournalEntry(
      index: 1, action: "tap", target: "Button",
      coords: "", before: "s1", beforeName: "S1",
      result: "same-screen", after: "", afterName: "",
      screenshot: nil, issue: nil
    )
    #expect(entry.screenAfter == nil)
  }

  @Test("screenAfter preserves value when non-empty")
  func screenAfterPreservedWhenPresent() {
    let entry = JournalLog.buildJournalEntry(
      index: 1, action: "tap", target: "Button",
      coords: "", before: "s1", beforeName: "S1",
      result: "navigated", after: "def67890", afterName: "Home",
      screenshot: nil, issue: nil
    )
    #expect(entry.screenAfter == "def67890")
  }

  @Test("screenAfterName is nil when afterName string is empty")
  func screenAfterNameNilWhenEmpty() {
    let entry = JournalLog.buildJournalEntry(
      index: 1, action: "tap", target: "Button",
      coords: "", before: "s1", beforeName: "S1",
      result: "navigated", after: "def67890", afterName: "",
      screenshot: nil, issue: nil
    )
    #expect(entry.screenAfterName == nil)
  }

  @Test("screenAfterName preserves value when non-empty")
  func screenAfterNamePreservedWhenPresent() {
    let entry = JournalLog.buildJournalEntry(
      index: 1, action: "tap", target: "Button",
      coords: "", before: "s1", beforeName: "S1",
      result: "navigated", after: "def67890", afterName: "Home",
      screenshot: nil, issue: nil
    )
    #expect(entry.screenAfterName == "Home")
  }

  @Test("Heading uses target when target is non-empty")
  func headingUsesTarget() {
    let heading = JournalLog.buildHeading(index: 1, action: "tap", target: "Sign In")
    #expect(heading == "### #1 — Sign In")
  }

  @Test("Heading uses action when target is empty")
  func headingUsesActionWhenNoTarget() {
    let heading = JournalLog.buildHeading(index: 1, action: "swipe", target: "")
    #expect(heading == "### #1 — swipe")
  }

  @Test("Screen line includes name when present")
  func screenLineIncludesName() {
    let line = JournalLog.buildScreenLine(prefix: "before", hash: "abc12345", name: "Welcome")
    #expect(line == "abc12345 — Welcome")
  }

  @Test("Screen line omits name separator when name is empty")
  func screenLineOmitsNameWhenEmpty() {
    let line = JournalLog.buildScreenLine(prefix: "before", hash: "abc12345", name: "")
    #expect(line == "abc12345")
    #expect(!line.contains("—"))
  }
}
