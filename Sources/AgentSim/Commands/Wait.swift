import ArgumentParser
import Foundation

struct Wait: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
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

          let output = WaitOutput(
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

private struct WaitOutput: Encodable {
  let ready: Bool
  let elementCount: Int
  let simulator: String
}

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
