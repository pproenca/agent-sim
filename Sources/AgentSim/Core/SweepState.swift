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

  enum ActionType: String, Encodable, Sendable {
    case tap
    case swipe
    case back
    case journalInit = "journal-init"
    case launch
    case recover
  }

  struct SuggestedNextAction: Encodable {
    let type: ActionType
    let target: String
    let command: String
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

// MARK: - JSON Sidecar Types

struct JournalEntry: Codable {
  let index: Int
  let action: String
  let target: String
  let coords: String?
  let screenBefore: String
  let screenBeforeName: String
  let result: String
  let screenAfter: String?
  let screenAfterName: String?
  let screenshot: String?
  let issue: String?
  let timestamp: String
}

struct JournalSidecar: Codable {
  let version: Int
  var entries: [JournalEntry]
}

// MARK: - Reader

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
    let currentDepth: Int
  }

  static func readJournal(at path: String) -> JournalState? {
    // Try JSON sidecar first
    let jsonPath = jsonSidecarPath(for: path)
    if FileManager.default.fileExists(atPath: jsonPath),
       let data = try? Data(contentsOf: URL(fileURLWithPath: jsonPath)),
       let sidecar = try? JSONDecoder().decode(JournalSidecar.self, from: data) {
      return computeStateFromEntries(sidecar.entries)
    }

    // Fall back to markdown parsing
    guard FileManager.default.fileExists(atPath: path),
          let content = try? String(contentsOfFile: path, encoding: .utf8)
    else { return nil }

    return parseMarkdown(content)
  }

  /// Compute the JSON sidecar path from a markdown journal path.
  static func jsonSidecarPath(for mdPath: String) -> String {
    if mdPath.hasSuffix(".md") {
      return String(mdPath.dropLast(3)) + ".json"
    }
    return mdPath + ".json"
  }

  // MARK: - JSON Path

  static func computeStateFromEntries(_ entries: [JournalEntry]) -> JournalState {
    var navigations = 0
    var sameScreen = 0
    var crashes = 0
    var issues = 0
    var screens = Set<String>()
    var tappedElements = Set<String>()
    var lastFingerprint: String?
    var lastScreenName: String?
    var currentDepth = 0

    for entry in entries {
      if !entry.screenBefore.isEmpty {
        screens.insert(entry.screenBefore)
      }

      let resultLower = entry.result.lowercased()
      if resultLower.contains("navigated") {
        navigations += 1
        // Depth tracking
        if entry.action.lowercased() == "back" {
          currentDepth = max(0, currentDepth - 1)
        } else {
          currentDepth += 1
        }
      } else if resultLower.contains("same") {
        sameScreen += 1
      } else if resultLower.contains("crash") {
        crashes += 1
        currentDepth = 0
      }

      if entry.issue != nil {
        issues += 1
      }

      if let after = entry.screenAfter, !after.isEmpty {
        screens.insert(after)
        lastFingerprint = after
        lastScreenName = entry.screenAfterName
      }

      if !entry.screenBefore.isEmpty && !entry.target.isEmpty {
        tappedElements.insert("\(entry.screenBefore):\(entry.target)")
      }
    }

    return JournalState(
      totalActions: entries.count,
      navigations: navigations,
      sameScreen: sameScreen,
      crashes: crashes,
      issues: issues,
      screens: screens,
      tappedElements: tappedElements,
      lastFingerprint: lastFingerprint,
      lastScreenName: lastScreenName,
      currentDepth: currentDepth
    )
  }

  // MARK: - Markdown Fallback

  private static func parseMarkdown(_ content: String) -> JournalState {
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
    var currentDepth = 0
    var currentAction: String?

    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      if trimmed.hasPrefix("### #") {
        totalActions += 1
        // Extract target from "### #1 — Target Name"
        if let dashRange = trimmed.range(of: "— ") {
          currentTarget = String(trimmed[dashRange.upperBound...])
        }
      }

      if trimmed.hasPrefix("- **Action**:") {
        currentAction = trimmed.replacingOccurrences(of: "- **Action**: ", with: "").lowercased()
      }

      if trimmed.hasPrefix("- **Result**:") {
        let result = trimmed.replacingOccurrences(of: "- **Result**: ", with: "").lowercased()
        if result.contains("navigated") {
          navigations += 1
          let isBack = currentAction == "back"
            || currentTarget?.lowercased() == "back"
          if isBack {
            currentDepth = max(0, currentDepth - 1)
          } else {
            currentDepth += 1
          }
        } else if result.contains("same") {
          sameScreen += 1
        } else if result.contains("crash") {
          crashes += 1
          currentDepth = 0
        }
      }

      if trimmed.hasPrefix("- **Issue**:") {
        issues += 1
      }

      if trimmed.hasPrefix("- **Screen before**:") {
        let hash = extractFingerprint(trimmed)
        if let hash {
          currentBeforeFingerprint = hash
          screens.insert(hash)
        }
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
      lastScreenName: lastScreenName,
      currentDepth: currentDepth
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
