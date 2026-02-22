import ArgumentParser
import Foundation

struct Assert: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Verify the current screen matches expectations. Returns exit code 0 on pass, 1 on fail."
  )

  @Option(name: .long, help: "Assert the screen contains an element with this label.")
  var contains: [String] = []

  @Option(name: .long, help: "Assert the screen does NOT contain an element with this label.")
  var notContains: [String] = []

  @Option(name: .long, help: "Assert the screen fingerprint matches this hash.")
  var fingerprint: String?

  @Option(name: .long, help: "Assert the screen name contains this text (case-insensitive).")
  var screenName: String?

  @Option(name: .long, help: "Assert at least this many interactive elements exist.")
  var minInteractive: Int?

  func validate() throws {
    let hasAny = !contains.isEmpty || !notContains.isEmpty ||
      fingerprint != nil || screenName != nil || minInteractive != nil
    guard hasAny else {
      throw ValidationError("Provide at least one assertion: --contains, --not-contains, --fingerprint, --screen-name, or --min-interactive.")
    }
  }

  func run() async throws {
    let device = try await SimulatorBridge.resolveDevice()
    let simNode = try await AXTreeReader.readDeviceTree(simulatorUDID: device.udid)
    let analysis = ScreenAnalyzer.analyze(simNode)
    let allElements = collectAllNames(simNode)

    var results: [AssertionResult] = []

    // Check --contains
    for label in contains {
      let found = allElements.contains(where: { $0.localizedCaseInsensitiveContains(label) })
      results.append(AssertionResult(
        assertion: "contains \"\(label)\"",
        passed: found,
        detail: found ? "Found" : "Not found. Available: \(allElements.prefix(10).joined(separator: ", "))"
      ))
    }

    // Check --not-contains
    for label in notContains {
      let found = allElements.contains(where: { $0.localizedCaseInsensitiveContains(label) })
      results.append(AssertionResult(
        assertion: "not-contains \"\(label)\"",
        passed: !found,
        detail: found ? "Unexpectedly found \"\(label)\"" : "Confirmed absent"
      ))
    }

    // Check --fingerprint
    if let expected = fingerprint {
      let actual = analysis.fingerprint
      let match = actual.hasPrefix(expected) || expected.hasPrefix(actual)
      results.append(AssertionResult(
        assertion: "fingerprint \"\(expected)\"",
        passed: match,
        detail: match ? "Matched" : "Got \(actual)"
      ))
    }

    // Check --screen-name
    if let expected = screenName {
      let match = analysis.screenName.localizedCaseInsensitiveContains(expected)
      results.append(AssertionResult(
        assertion: "screen-name \"\(expected)\"",
        passed: match,
        detail: match ? "Matched: \(analysis.screenName)" : "Got: \(analysis.screenName)"
      ))
    }

    // Check --min-interactive
    if let minCount = minInteractive {
      let actual = analysis.interactiveCount
      let passed = actual >= minCount
      results.append(AssertionResult(
        assertion: "min-interactive \(minCount)",
        passed: passed,
        detail: "Found \(actual) interactive elements"
      ))
    }

    // Output
    let allPassed = results.allSatisfy(\.passed)
    let output = AssertOutput(
      passed: allPassed,
      screenName: analysis.screenName,
      fingerprint: analysis.fingerprint,
      assertions: results
    )

    JSONOutput.print(output)

    if !allPassed {
      throw ExitCode.failure
    }
  }

  private func collectAllNames(_ node: AXNode) -> [String] {
    var names: [String] = []
    if !node.displayName.isEmpty {
      names.append(node.displayName)
    }
    for child in node.children {
      names.append(contentsOf: collectAllNames(child))
    }
    return names
  }
}

private struct AssertionResult: Encodable {
  let assertion: String
  let passed: Bool
  let detail: String
}

private struct AssertOutput: Encodable {
  let passed: Bool
  let screenName: String
  let fingerprint: String
  let assertions: [AssertionResult]
}
