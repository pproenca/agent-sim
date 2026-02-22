import ArgumentParser
import Foundation

struct Tap: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Tap an element on the simulator screen."
  )

  @Option(name: .long, help: "Tap element by accessibility label.")
  var label: String?

  @Option(name: .long, help: "Tap element by accessibility identifier.")
  var id: String?

  @Option(name: .long, help: "Tap element by box number from the last annotated explore.")
  var box: Int?

  @Argument(help: "X coordinate (simulator-relative).")
  var x: Int?

  @Argument(help: "Y coordinate (simulator-relative).")
  var y: Int?

  @Flag(name: .long, help: "Describe the screen after tapping.")
  var describe = false

  @Option(name: .long, help: "Delay in seconds after tap before describing.")
  var delay: Double = 0.8

  func validate() throws {
    let hasCoords = x != nil && y != nil
    let hasLabel = label != nil
    let hasID = id != nil
    let hasBox = box != nil
    guard hasCoords || hasLabel || hasID || hasBox else {
      throw ValidationError("Provide coordinates (x y), --label, --id, or --box N.")
    }
  }

  func run() async throws {
    let device = try await SimulatorBridge.resolveDevice()

    var tapX: Int
    var tapY: Int

    if let box {
      let entry = try findBoxEntry(box)
      tapX = entry.tapX
      tapY = entry.tapY
      printStatus("Tapping #\(box) \"\(entry.label)\" at (\(tapX),\(tapY))")
    } else if let label {
      let (node, tapCoords) = try await findElement(simulatorUDID: device.udid, label: label, id: nil)
      tapX = tapCoords.0
      tapY = tapCoords.1
      printStatus("Tapping \"\(node.displayName)\" at (\(tapX),\(tapY))")
    } else if let id {
      let (node, tapCoords) = try await findElement(simulatorUDID: device.udid, label: nil, id: id)
      tapX = tapCoords.0
      tapY = tapCoords.1
      printStatus("Tapping \"\(node.displayName)\" at (\(tapX),\(tapY))")
    } else {
      tapX = x!
      tapY = y!
      printStatus("Tapping at (\(tapX),\(tapY))")
    }

    try await SimulatorBridge.tap(x: tapX, y: tapY, simulatorID: device.udid)

    if describe {
      try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      if let descNode = try? await AXTreeReader.readDeviceTree(simulatorUDID: device.udid) {
        JSONOutput.print(descNode)
      }
    }
  }

  private func findBoxEntry(_ boxNumber: Int) throws -> ScreenAnnotator.BoxEntry {
    let path = ScreenAnnotator.defaultMappingPath
    guard FileManager.default.fileExists(atPath: path) else {
      throw TapError.noBoxMapping
    }
    let entries = try ScreenAnnotator.loadBoxMapping(from: path)
    guard let entry = entries.first(where: { $0.box == boxNumber }) else {
      let available = entries.map { "#\($0.box) \"\($0.label)\"" }.joined(separator: ", ")
      throw TapError.boxNotFound(boxNumber, available: available)
    }
    return entry
  }

  private func findElement(simulatorUDID: String, label: String?, id: String?) async throws -> (AXNode, (Int, Int)) {
    let simNode = try await AXTreeReader.readDeviceTree(simulatorUDID: simulatorUDID)
    let interactive = AXTreeReader.collectInteractive(simNode)

    let match: AXNode?
    if let label {
      match = interactive.first { $0.displayName == label }
        ?? interactive.first { $0.displayName.localizedCaseInsensitiveContains(label) }
    } else if let id {
      match = interactive.first { $0.identifier == id }
    } else {
      match = nil
    }

    guard let found = match else {
      let names = interactive.map { "\"\($0.displayName)\"" }.joined(separator: ", ")
      throw TapError.elementNotFound(label ?? id ?? "?", available: names)
    }

    return (found, (Int(found.frame.centerX), Int(found.frame.centerY)))
  }

  private func printStatus(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
  }
}

enum TapError: Error, LocalizedError {
  case elementNotFound(String, available: String)
  case noBoxMapping
  case boxNotFound(Int, available: String)

  var errorDescription: String? {
    switch self {
    case .elementNotFound(let target, let available):
      "Element not found: \"\(target)\". Available: \(available)"
    case .noBoxMapping:
      "No box mapping found. Run `explore --annotate` first."
    case .boxNotFound(let box, let available):
      "Box #\(box) not found. Available: \(available)"
    }
  }
}
