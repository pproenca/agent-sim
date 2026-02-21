import ArgumentParser
import Foundation

struct SwipeCmd: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "swipe",
    abstract: "Swipe on the simulator screen."
  )

  @Argument(help: "Swipe direction: up, down, left, right.")
  var direction: String

  @Option(name: .long, help: "Swipe distance in points.")
  var delta: Int = 300

  @Option(name: .long, help: "Swipe duration in seconds.")
  var duration: Double = 0.5

  @Flag(name: .long, help: "Describe the screen after swiping.")
  var describe = false

  @Option(name: .long, help: "Delay in seconds after swipe before describing.")
  var delay: Double = 0.8

  func validate() throws {
    guard ["up", "down", "left", "right"].contains(direction.lowercased()) else {
      throw ValidationError("Direction must be one of: up, down, left, right.")
    }
  }

  func run() async throws {
    let device = try await SimulatorBridge.resolveDevice()

    guard let swipeDir = SimulatorBridge.SwipeDirection(rawValue: direction.lowercased()) else {
      throw ValidationError("Invalid direction: \(direction)")
    }

    try await SimulatorBridge.swipe(direction: swipeDir, simulatorID: device.udid, duration: duration, delta: delta)

    if describe {
      try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

      if let descNode = try? await AXTreeReader.readDeviceTree(simulatorUDID: device.udid) {
        let analysis = ScreenAnalyzer.analyze(descNode)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(analysis) {
          print(String(data: data, encoding: .utf8) ?? "{}")
        }
      }
    }
  }
}
