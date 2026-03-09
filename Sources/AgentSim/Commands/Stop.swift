import ArgumentParser
import Foundation

struct Stop: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "stop",
    abstract: "Stop a running app on the simulator."
  )

  @Argument(help: "Bundle identifier of the app to stop.")
  var bundleID: String

  @Option(name: .long, help: "Target a specific simulator by UDID.")
  var udid: String?

  func run() async throws {
    let device = try await SimulatorBridge.resolveDevice(udid: udid)
    try await SimulatorBridge.terminate(simulatorID: device.udid, bundleID: bundleID)
    let output = StopOutput(status: "stopped", bundleID: bundleID, simulator: device.name)
    JSONOutput.print(output)
  }
}

private struct StopOutput: Encodable {
  let status: String
  let bundleID: String
  let simulator: String
}
