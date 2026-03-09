import ArgumentParser
import Foundation

// MARK: - ui (parent group)

struct UIGroup: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "ui",
    abstract: "UI inspection and assertions: assert, wait, find.",
    subcommands: [
      UIAssertGroup.self,
      UIWait.self,
      UIFind.self,
    ]
  )
}

// MARK: - ui assert (parent group)

struct UIAssertGroup: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "assert",
    abstract: "Assert UI element state: visible, hidden, text, enabled.",
    subcommands: [
      UIAssertVisible.self,
      UIAssertHidden.self,
      UIAssertText.self,
      UIAssertEnabled.self,
    ]
  )
}

// MARK: - ui assert visible

struct UIAssertVisible: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "visible",
    abstract: "Assert an element with the given label is visible on screen."
  )

  @Argument(help: "Label to search for (case-insensitive).")
  var label: String

  func run() async throws {
    let device = try await SimulatorBridge.resolveDevice()
    let tree = try await AXTreeReader.readDeviceTree(simulatorUDID: device.udid)
    let allNames = collectAllNames(tree)

    let found = allNames.contains(where: { $0.localizedCaseInsensitiveContains(label) })
    let output = UIAssertOutput(
      passed: found,
      assertion: "visible \"\(label)\"",
      detail: found ? "Found" : "Not found. Available: \(allNames.prefix(10).joined(separator: ", "))"
    )
    JSONOutput.print(output)

    if !found {
      throw ExitCode.failure
    }
  }
}

// MARK: - ui assert hidden

struct UIAssertHidden: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "hidden",
    abstract: "Assert an element with the given label is NOT visible on screen."
  )

  @Argument(help: "Label to search for (case-insensitive).")
  var label: String

  func run() async throws {
    let device = try await SimulatorBridge.resolveDevice()
    let tree = try await AXTreeReader.readDeviceTree(simulatorUDID: device.udid)
    let allNames = collectAllNames(tree)

    let found = allNames.contains(where: { $0.localizedCaseInsensitiveContains(label) })
    let output = UIAssertOutput(
      passed: !found,
      assertion: "hidden \"\(label)\"",
      detail: found ? "Unexpectedly found \"\(label)\"" : "Confirmed absent"
    )
    JSONOutput.print(output)

    if found {
      throw ExitCode.failure
    }
  }
}

// MARK: - ui assert text

struct UIAssertText: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "text",
    abstract: "Assert an element's value matches expected text."
  )

  @Argument(help: "Label of the element to find (case-insensitive).")
  var label: String

  @Argument(help: "Expected text value.")
  var expected: String

  func run() async throws {
    let device = try await SimulatorBridge.resolveDevice()
    let tree = try await AXTreeReader.readDeviceTree(simulatorUDID: device.udid)
    let allNodes = tree.flattened()

    let match = allNodes.first(where: {
      $0.displayName.localizedCaseInsensitiveContains(label)
    })

    guard let element = match else {
      let output = UIAssertOutput(
        passed: false,
        assertion: "text \"\(label)\" == \"\(expected)\"",
        detail: "Element \"\(label)\" not found"
      )
      JSONOutput.print(output)
      throw ExitCode.failure
    }

    let actual = element.value.isEmpty ? element.displayName : element.value
    let passed = actual == expected
    let output = UIAssertOutput(
      passed: passed,
      assertion: "text \"\(label)\" == \"\(expected)\"",
      detail: passed ? "Matched" : "Got \"\(actual)\""
    )
    JSONOutput.print(output)

    if !passed {
      throw ExitCode.failure
    }
  }
}

// MARK: - ui assert enabled

struct UIAssertEnabled: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "enabled",
    abstract: "Assert an element with the given label is enabled."
  )

  @Argument(help: "Label of the element to find (case-insensitive).")
  var label: String

  func run() async throws {
    let device = try await SimulatorBridge.resolveDevice()
    let tree = try await AXTreeReader.readDeviceTree(simulatorUDID: device.udid)
    let allNodes = tree.flattened()

    let match = allNodes.first(where: {
      $0.displayName.localizedCaseInsensitiveContains(label)
    })

    guard let element = match else {
      let output = UIAssertOutput(
        passed: false,
        assertion: "enabled \"\(label)\"",
        detail: "Element \"\(label)\" not found"
      )
      JSONOutput.print(output)
      throw ExitCode.failure
    }

    let output = UIAssertOutput(
      passed: element.enabled,
      assertion: "enabled \"\(label)\"",
      detail: element.enabled ? "Element is enabled" : "Element is disabled"
    )
    JSONOutput.print(output)

    if !element.enabled {
      throw ExitCode.failure
    }
  }
}

// MARK: - ui wait

struct UIWait: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "wait",
    abstract: "Wait until the simulator is ready for interaction."
  )

  @Option(name: .long, help: "Timeout in seconds (default: 30).")
  var timeout: Int = 30

  @Option(name: .long, help: "Wait for a specific app to be frontmost (bundle ID).")
  var app: String?

  func run() async throws {
    let device = try await SimulatorBridge.resolveDevice()
    let deadline = Date().addingTimeInterval(Double(timeout))
    var delayNs: UInt64 = 200_000_000 // 200ms initial

    while Date() < deadline {
      if let tree = try? await AXTreeReader.readDeviceTree(
        simulatorUDID: device.udid, maxDepth: 3
      ) {
        let total = AXTreeReader.totalCount(tree)
        if total > 0 {
          // If --app specified, verify we're not on SpringBoard
          if app != nil {
            let isSpringBoard = tree.label == "SpringBoard"
              || tree.identifier == "com.apple.springboard"
            if isSpringBoard {
              try await Task.sleep(nanoseconds: delayNs)
              delayNs = min(delayNs * 2, 2_000_000_000)
              continue
            }
          }

          let output = UIWaitOutput(
            ready: true,
            elementCount: total,
            simulator: device.name
          )
          JSONOutput.print(output)
          return
        }
      }

      try await Task.sleep(nanoseconds: delayNs)
      delayNs = min(delayNs * 2, 2_000_000_000) // max 2s
    }

    throw WaitError.timeout(timeout)
  }
}

// MARK: - ui find

struct UIFind: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "find",
    abstract: "Find UI elements by label, identifier, or role (case-insensitive substring match)."
  )

  @Argument(help: "Search query (matches label, identifier, or role).")
  var query: String

  func run() async throws {
    let device = try await SimulatorBridge.resolveDevice()
    let tree = try await AXTreeReader.readDeviceTree(simulatorUDID: device.udid)
    let allNodes = tree.flattened()

    let matches = allNodes.filter { node in
      node.label.localizedCaseInsensitiveContains(query)
        || node.identifier.localizedCaseInsensitiveContains(query)
        || node.role.localizedCaseInsensitiveContains(query)
    }

    let results = matches.map { node in
      UIFindResult(
        role: node.role,
        name: node.displayName,
        identifier: node.identifier,
        tapX: Int(node.frame.centerX),
        tapY: Int(node.frame.centerY),
        width: Int(node.frame.width),
        height: Int(node.frame.height),
        enabled: node.enabled
      )
    }

    JSONOutput.print(results)
  }
}

// MARK: - Shared helpers

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

// MARK: - Output types

private struct UIAssertOutput: Encodable {
  let passed: Bool
  let assertion: String
  let detail: String
}

private struct UIWaitOutput: Encodable {
  let ready: Bool
  let elementCount: Int
  let simulator: String
}

private struct UIFindResult: Encodable {
  let role: String
  let name: String
  let identifier: String
  let tapX: Int
  let tapY: Int
  let width: Int
  let height: Int
  let enabled: Bool
}

// MARK: - Errors

enum WaitError: Error, LocalizedError {
  case timeout(Int)

  var errorDescription: String? {
    switch self {
    case .timeout(let seconds):
      "Timed out after \(seconds)s waiting for simulator to be ready. " +
      "Ensure the simulator is booted and an app is running."
    }
  }
}
