/// Pre-built journal markdown fixtures for SweepStateReader tests.
import Foundation

enum JournalFixtures {

  static let empty = """
    # Sweep Journal

    ## Metadata

    - **Started**: 2026-02-21T10:00:00Z
    - **Simulator**: iPhone 16
    - **Scope**: Full app exploration
    - **Status**: in-progress

    ## Actions

    """

  static let threeActions = """
    # Sweep Journal

    ## Metadata

    - **Started**: 2026-02-21T10:00:00Z
    - **Simulator**: iPhone 16
    - **Scope**: Full app exploration
    - **Status**: in-progress

    ## Actions

    ### #1 — Sign In

    - **Action**: tap
    - **Coordinates**: (196,426)
    - **Screen before**: abc12345 — Welcome
    - **Result**: navigated
    - **Screen after**: def67890 — Home

    ### #2 — View Profile

    - **Action**: tap
    - **Coordinates**: (350,50)
    - **Screen before**: def67890 — Home
    - **Result**: navigated
    - **Screen after**: ghi11111 — Profile

    ### #3 — Back

    - **Action**: tap
    - **Coordinates**: (30,50)
    - **Screen before**: ghi11111 — Profile
    - **Result**: navigated
    - **Screen after**: def67890 — Home

    """

  static let withIssuesAndCrash = """
    # Sweep Journal

    ## Metadata

    - **Started**: 2026-02-21T10:00:00Z
    - **Simulator**: iPhone 16
    - **Scope**: Full app exploration
    - **Status**: in-progress

    ## Actions

    ### #1 — Sign In

    - **Action**: tap
    - **Screen before**: abc12345 — Welcome
    - **Result**: navigated
    - **Screen after**: def67890 — Home

    ### #2 — Preparation Card

    - **Action**: tap
    - **Screen before**: def67890 — Home
    - **Result**: same-screen
    - **Issue**: Preparation card tap does not navigate

    ### #3 — Profile Button

    - **Action**: tap
    - **Screen before**: def67890 — Home
    - **Result**: crash
    - **Issue**: App crashed after profile button tap

    ### #4 — Recovery

    - **Action**: crash-recovery
    - **Screen before**: def67890 — Home
    - **Result**: navigated
    - **Screen after**: abc12345 — Welcome

    """

  static let sameScreenOnly = """
    # Sweep Journal

    ## Metadata

    - **Started**: 2026-02-21T10:00:00Z
    - **Simulator**: iPhone 16
    - **Scope**: Full app exploration
    - **Status**: in-progress

    ## Actions

    ### #1 — Button A

    - **Action**: tap
    - **Screen before**: aaa11111 — Settings
    - **Result**: same-screen
    - **Screen after**: aaa11111 — Settings

    ### #2 — Button B

    - **Action**: tap
    - **Screen before**: aaa11111 — Settings
    - **Result**: same-screen
    - **Screen after**: aaa11111 — Settings

    """

  /// Write fixture content to a temporary file and return the path.
  static func writeTempFile(_ content: String, name: String = "test-journal.md") -> String {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("agentsim-tests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let path = dir.appendingPathComponent(name).path
    try! content.write(toFile: path, atomically: true, encoding: .utf8)
    return path
  }
}
