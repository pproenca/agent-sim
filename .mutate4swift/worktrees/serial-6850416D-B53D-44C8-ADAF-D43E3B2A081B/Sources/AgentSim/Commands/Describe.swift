import ArgumentParser
import Foundation

struct Describe: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Describe the current screen's accessibility tree."
  )

  @Flag(name: .long, help: "Only show interactive elements with tap coordinates.")
  var interactive = false

  @Flag(name: .long, help: "Pretty-print the tree instead of JSON.")
  var pretty = false

  @Option(name: .long, help: "Maximum tree depth.")
  var maxDepth: Int = 20

  func run() async throws {
    let device = try await SimulatorBridge.resolveDevice()
    let simNode = try await AXTreeReader.readDeviceTree(simulatorUDID: device.udid, maxDepth: maxDepth)

    if interactive {
      let elements = AXTreeReader.collectInteractive(simNode)
      if pretty {
        printInteractivePretty(elements)
      } else {
        JSONOutput.print(elements.map(InteractiveElement.init))
      }
    } else {
      if pretty {
        printTreePretty(simNode)
        printStats(simNode)
      } else {
        JSONOutput.print(simNode)
      }
    }
  }

  private func printTreePretty(_ node: AXNode, indent: Int = 0) {
    let pad = String(repeating: "  ", count: indent)
    var parts: [String] = [node.role]
    if !node.label.isEmpty { parts.append("label=\"\(node.label)\"") }
    if !node.identifier.isEmpty { parts.append("id=\"\(node.identifier)\"") }
    if !node.accessibilityDescription.isEmpty && node.accessibilityDescription.count < 80 {
      parts.append("desc=\"\(node.accessibilityDescription)\"")
    }
    if !node.value.isEmpty && node.value.count < 60 { parts.append("value=\"\(node.value)\"") }
    if !node.enabled { parts.append("DISABLED") }
    if node.frame.width > 0 {
      parts.append("(\(Int(node.frame.x)),\(Int(node.frame.y)) \(Int(node.frame.width))x\(Int(node.frame.height)))")
    }
    print("\(pad)\(parts.joined(separator: " "))")
    for child in node.children {
      printTreePretty(child, indent: indent + 1)
    }
  }

  private func printStats(_ node: AXNode) {
    let total = AXTreeReader.totalCount(node)
    let interactive = AXTreeReader.collectInteractive(node)
    let byRole = AXTreeReader.countByRole(node)

    print("\n--- Stats ---")
    print("Elements: \(total)  Interactive: \(interactive.count)")
    print("Roles: \(byRole.sorted(by: { $0.value > $1.value }).map { "\($0.key):\($0.value)" }.joined(separator: " "))")
  }

  private func printInteractivePretty(_ elements: [AXNode]) {
    for el in elements {
      let cx = Int(el.frame.centerX)
      let cy = Int(el.frame.centerY)
      print("[\(el.role)] \"\(el.displayName)\" tap=(\(cx),\(cy)) size=\(Int(el.frame.width))x\(Int(el.frame.height))")
    }
  }

}

// MARK: - JSON output model for interactive elements

private struct InteractiveElement: Encodable {
  let role: String
  let name: String
  let identifier: String
  let tapX: Int
  let tapY: Int
  let width: Int
  let height: Int
  let enabled: Bool

  init(_ node: AXNode) {
    role = node.role
    name = node.displayName
    identifier = node.identifier
    tapX = Int(node.frame.centerX)
    tapY = Int(node.frame.centerY)
    width = Int(node.frame.width)
    height = Int(node.frame.height)
    enabled = node.enabled
  }
}

// MARK: - Errors

enum DescribeError: Error, LocalizedError {
  case noScreenContent

  var errorDescription: String? {
    switch self {
    case .noScreenContent:
      "Could not find iOS app content in the Simulator's accessibility tree."
    }
  }
}
