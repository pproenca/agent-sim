import ArgumentParser
import Foundation

struct SwipeCmd: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "swipe",
    abstract: "Swipe on the simulator screen."
  )

  @Argument(help: "Swipe direction: up, down, left, right.")
  var direction: SimulatorBridge.SwipeDirection

  @Option(name: .long, help: "Swipe distance in points.")
  var delta: Int = 300

  @Option(name: .long, help: "Swipe duration in seconds.")
  var duration: Double = 0.5

  @Flag(name: .long, help: "Describe the screen after swiping.")
  var describe = false

  @Option(name: .long, help: "Delay in seconds after swipe before describing.")
  var delay: Double = 0.8

  func run() async throws {
    let device = try await SimulatorBridge.resolveDevice()
    let (x1, y1, x2, y2) = direction.coordinates(
      delta: delta,
      screenWidth: Int(device.screenWidthPoints),
      screenHeight: Int(device.screenHeightPoints)
    )

    try await SimulatorBridge.swipe(
      from: (x: x1, y: y1), to: (x: x2, y: y2),
      duration: duration, simulatorID: device.udid
    )

    // Auto-log
    ActionLogger.log(ActionLogger.entry(action: "swipe", target: direction.rawValue))

    if describe {
      try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

      if let descNode = try? await AXTreeReader.readDeviceTree(simulatorUDID: device.udid) {
        let analysis = ScreenAnalyzer.analyze(descNode)
        JSONOutput.print(analysis)
      }
    } else {
      print("Done")
    }
  }
}
