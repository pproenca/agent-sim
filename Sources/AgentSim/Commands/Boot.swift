import ArgumentParser
import Foundation

struct Boot: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Boot a simulator. Waits until fully usable before returning."
  )

  @Argument(help: "Simulator name (e.g. 'iPhone 16'). Boots first available if omitted.")
  var name: String?

  @Option(name: .long, help: "Boot a specific simulator by UDID.")
  var udid: String?

  @Flag(name: .long, help: "List available (shutdown) simulators instead of booting.")
  var list = false

  func run() async throws {
    if list {
      try await listShutdown()
      return
    }

    if let udid {
      try await SimulatorBridge.boot(udid: udid)
      let device = try await SimulatorBridge.resolveDevice()
      printBooted(device)
    } else {
      let device = try await SimulatorBridge.bootByName(name)
      printBooted(device)
    }
  }

  private func listShutdown() async throws {
    let all = try await SimulatorBridge.allDevices()
    let shutdown = all.filter { $0.state.contains("shutdown") || $0.state.contains("Shutdown") }

    if shutdown.isEmpty {
      print("No shutdown simulators available.")
      return
    }

    print("Available simulators (\(shutdown.count)):")
    for device in shutdown {
      print("  \(device.name)  \(device.udid)")
    }
  }

  private func printBooted(_ device: SimulatorBridge.BootedDevice) {
    let output = BootOutput(
      status: "booted",
      udid: device.udid,
      name: device.name,
      screenWidth: Int(device.screenWidthPoints),
      screenHeight: Int(device.screenHeightPoints)
    )
    JSONOutput.print(output)
  }
}

private struct BootOutput: Encodable {
  let status: String
  let udid: String
  let name: String
  let screenWidth: Int
  let screenHeight: Int
}
