import Foundation

/// Typed sweep state — the agent branches on this, never on free text.
/// Modeled after OpenSpec's artifact status pattern.
enum SweepPhase: String, Encodable {
  /// No journal exists yet. Agent should initialize.
  case notStarted = "not_started"
  /// Journal exists, elements remain on current screen.
  case exploring
  /// All elements on current screen tapped. Need to navigate deeper or back up.
  case screenExhausted = "screen_exhausted"
  /// Navigated to a new screen that hasn't been explored yet.
  case newScreen = "new_screen"
  /// App crashed or is unresponsive. Agent needs to recover.
  case crashed
  /// All reachable screens explored within depth/screen limits.
  case complete
}

/// The output of the `next` command — tells the agent exactly what to do.
/// Equivalent to OpenSpec's `instructions` command output.
struct NextInstruction: Encodable {
  let phase: SweepPhase
  let instruction: String
  let action: SuggestedNextAction?
  let currentScreen: ScreenSnapshot?
  let progress: SweepProgress
  let afterAction: [String]
  let guardrails: [String]

  struct SuggestedNextAction: Encodable {
    let type: String          // "tap", "swipe", "back", "journal-init", "launch", "recover"
    let target: String        // element name or description
    let command: String       // exact CLI command to run
    let reason: String
    let tapX: Int?
    let tapY: Int?
  }

  struct ScreenSnapshot: Encodable {
    let name: String
    let fingerprint: String
    let interactiveCount: Int
    let tappedCount: Int
    let remainingCount: Int
  }

  struct SweepProgress: Encodable {
    let screensVisited: Int
    let totalActions: Int
    let issuesFound: Int
    let crashesDetected: Int
    let journalPath: String?
  }
}

/// Reads a journal file and computes sweep state.
enum SweepStateReader {

  struct JournalState {
    let totalActions: Int
    let navigations: Int
    let sameScreen: Int
    let crashes: Int
    let issues: Int
    let screens: Set<String>
    let tappedElements: Set<String> // "fingerprint:target" pairs
    let lastFingerprint: String?
    let lastScreenName: String?
  }

  static func readJournal(at path: String) -> JournalState? {
    guard FileManager.default.fileExists(atPath: path),
          let content = try? String(contentsOfFile: path, encoding: .utf8)
    else { return nil }

    let lines = content.components(separatedBy: "\n")

    var totalActions = 0
    var navigations = 0
    var sameScreen = 0
    var crashes = 0
    var issues = 0
    var screens = Set<String>()
    var tappedElements = Set<String>()
    var lastFingerprint: String?
    var lastScreenName: String?
    var currentBeforeFingerprint: String?
    var currentTarget: String?

    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      if trimmed.hasPrefix("### #") {
        totalActions += 1
        // Extract target from "### #1 — Target Name"
        if let dashRange = trimmed.range(of: "— ") {
          currentTarget = String(trimmed[dashRange.upperBound...])
        }
      }

      if trimmed.hasPrefix("- **Result**:") {
        let result = trimmed.replacingOccurrences(of: "- **Result**: ", with: "").lowercased()
        if result.contains("navigated") { navigations += 1 }
        else if result.contains("same") { sameScreen += 1 }
        else if result.contains("crash") { crashes += 1 }
      }

      if trimmed.hasPrefix("- **Issue**:") {
        issues += 1
      }

      if trimmed.hasPrefix("- **Screen before**:") {
        let hash = extractFingerprint(trimmed)
        if let hash { currentBeforeFingerprint = hash }
      }

      if trimmed.hasPrefix("- **Screen after**:") {
        let hash = extractFingerprint(trimmed)
        if let hash {
          screens.insert(hash)
          lastFingerprint = hash

          // Extract screen name
          if let dashRange = trimmed.range(of: " — ") {
            lastScreenName = String(trimmed[dashRange.upperBound...])
          }
        }

        // Record tapped element
        if let before = currentBeforeFingerprint, let target = currentTarget {
          tappedElements.insert("\(before):\(target)")
        }
      }

      if trimmed.hasPrefix("- **Screen before**:") {
        let hash = extractFingerprint(trimmed)
        if let hash { screens.insert(hash) }
      }
    }

    return JournalState(
      totalActions: totalActions,
      navigations: navigations,
      sameScreen: sameScreen,
      crashes: crashes,
      issues: issues,
      screens: screens,
      tappedElements: tappedElements,
      lastFingerprint: lastFingerprint,
      lastScreenName: lastScreenName
    )
  }

  private static func extractFingerprint(_ line: String) -> String? {
    // Extract hash from "- **Screen before**: abc12345 — Screen Name"
    let parts = line.components(separatedBy: ": ")
    guard parts.count >= 2 else { return nil }
    let afterColon = parts.dropFirst().joined(separator: ": ")
    let hash = afterColon.components(separatedBy: " ").first
    return hash?.isEmpty == false ? hash : nil
  }
}
