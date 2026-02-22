import ArgumentParser
import Foundation

struct Journal: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Manage sweep journals for QA exploration sessions.",
    subcommands: [JournalInit.self, JournalLog.self, JournalSummary.self]
  )
}

// MARK: - Init

struct JournalInit: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "init",
    abstract: "Create a new sweep journal file."
  )

  @Option(name: .long, help: "Output path for the journal file.")
  var path: String?

  @Option(name: .long, help: "Name of the simulator being tested.")
  var simulator: String = "Unknown"

  @Option(name: .long, help: "Description of the sweep scope.")
  var scope: String = "Full app exploration"

  func run() throws {
    let outputPath = path ?? defaultJournalPath()

    // Ensure parent directory exists
    let dir = (outputPath as NSString).deletingLastPathComponent
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

    let timestamp = ISO8601DateFormatter().string(from: Date())
    let content = """
      # Sweep Journal

      ## Metadata

      - **Started**: \(timestamp)
      - **Simulator**: \(simulator)
      - **Scope**: \(scope)
      - **Status**: in-progress

      ## Actions

      """

    try content.write(toFile: outputPath, atomically: true, encoding: .utf8)

    // Create empty JSON sidecar
    let jsonPath = SweepStateReader.jsonSidecarPath(for: outputPath)
    let sidecar = JournalSidecar(version: 1, entries: [])
    let jsonData = try JSONEncoder().encode(sidecar)
    try jsonData.write(to: URL(fileURLWithPath: jsonPath), options: .atomic)

    print(outputPath)
  }

  private func defaultJournalPath() -> String {
    ProjectConfig.defaultJournalPath()
  }
}

// MARK: - Log

struct JournalLog: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "log",
    abstract: "Append an action entry to a sweep journal."
  )

  @Option(name: .long, help: "Path to the journal file.")
  var path: String

  @Option(name: .long, help: "Action index number.")
  var index: Int

  @Option(name: .long, help: "What was tapped or done.")
  var action: String

  @Option(name: .long, help: "Element label or description.")
  var target: String = ""

  @Option(name: .long, help: "Tap coordinates (e.g., '150,300').")
  var coords: String = ""

  @Option(name: .long, help: "Screen fingerprint before the action.")
  var before: String = ""

  @Option(name: .long, help: "Screen name before the action.")
  var beforeName: String = ""

  @Option(name: .long, help: "Screen fingerprint after the action.")
  var after: String = ""

  @Option(name: .long, help: "Screen name after the action.")
  var afterName: String = ""

  @Option(name: .long, help: "Result: navigated, same-screen, crash, error.")
  var result: String

  @Option(name: .long, help: "Path to screenshot taken.")
  var screenshot: String?

  @Option(name: .long, help: "Any issue or anomaly detected.")
  var issue: String?

  func run() throws {
    guard FileManager.default.fileExists(atPath: path) else {
      throw JournalError.fileNotFound(path)
    }

    var entry = """

      ### #\(index) — \(target.isEmpty ? action : target)

      - **Action**: \(action)
      """

    if !coords.isEmpty {
      entry += "\n- **Coordinates**: (\(coords))"
    }
    if !before.isEmpty {
      entry += "\n- **Screen before**: \(before)\(beforeName.isEmpty ? "" : " — \(beforeName)")"
    }

    entry += "\n- **Result**: \(result)"

    if !after.isEmpty {
      entry += "\n- **Screen after**: \(after)\(afterName.isEmpty ? "" : " — \(afterName)")"
    }
    if let screenshot {
      entry += "\n- **Screenshot**: \(screenshot)"
    }
    if let issue {
      entry += "\n- **Issue**: \(issue)"
    }

    entry += "\n"

    let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
    handle.seekToEndOfFile()
    handle.write(Data(entry.utf8))
    handle.closeFile()

    // Update JSON sidecar
    let jsonPath = SweepStateReader.jsonSidecarPath(for: path)
    let journalEntry = JournalEntry(
      index: index,
      action: action,
      target: target,
      coords: coords.isEmpty ? nil : coords,
      screenBefore: before,
      screenBeforeName: beforeName,
      result: result,
      screenAfter: after.isEmpty ? nil : after,
      screenAfterName: afterName.isEmpty ? nil : afterName,
      screenshot: screenshot,
      issue: issue,
      timestamp: ISO8601DateFormatter().string(from: Date())
    )

    var sidecar: JournalSidecar
    if let data = try? Data(contentsOf: URL(fileURLWithPath: jsonPath)),
       let existing = try? JSONDecoder().decode(JournalSidecar.self, from: data) {
      sidecar = existing
    } else {
      sidecar = JournalSidecar(version: 1, entries: [])
    }
    sidecar.entries.append(journalEntry)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let jsonData = try encoder.encode(sidecar)
    try jsonData.write(to: URL(fileURLWithPath: jsonPath), options: .atomic)
  }
}

// MARK: - Summary

struct JournalSummary: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "summary",
    abstract: "Print a summary of a sweep journal."
  )

  @Option(name: .long, help: "Path to the journal file.")
  var path: String

  func run() throws {
    guard FileManager.default.fileExists(atPath: path) else {
      throw JournalError.fileNotFound(path)
    }

    guard let state = SweepStateReader.readJournal(at: path) else {
      throw JournalError.fileNotFound(path)
    }

    let summary = JournalSummaryOutput(
      totalActions: state.totalActions,
      navigations: state.navigations,
      sameScreen: state.sameScreen,
      crashes: state.crashes,
      issues: state.issues,
      uniqueScreens: state.screens.count
    )

    JSONOutput.print(summary)
  }
}

// MARK: - Models

private struct JournalSummaryOutput: Encodable {
  let totalActions: Int
  let navigations: Int
  let sameScreen: Int
  let crashes: Int
  let issues: Int
  let uniqueScreens: Int
}

// MARK: - Errors

enum JournalError: Error, CustomStringConvertible {
  case fileNotFound(String)

  var description: String {
    switch self {
    case .fileNotFound(let path):
      "Journal file not found: \(path)"
    }
  }
}

// MARK: - Date Formatter

extension DateFormatter {
  fileprivate static let fileDate: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd-HHmmss"
    return f
  }()
}
