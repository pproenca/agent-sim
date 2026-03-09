import ArgumentParser
import Foundation

struct Launch: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Launch an app on the booted simulator."
  )

  @Argument(help: "Bundle identifier of the app to launch.")
  var bundleID: String

  @Option(name: .long, parsing: .upToNextOption, help: "Arguments to pass to the app.")
  var args: [String] = []

  @Option(name: .long, help: "Target a specific simulator by UDID, bypassing the device pin.")
  var udid: String?

  @Flag(name: .long, help: "Enable CFNetwork HTTP diagnostics for agent-sim network.")
  var network = false

  func run() async throws {
    let device = try await SimulatorBridge.resolveDevice(udid: udid)
    var env: [String: String] = [:]
    if network {
      env["CFNETWORK_DIAGNOSTICS"] = "3"
    }
    try await SimulatorBridge.launch(
      simulatorID: device.udid, bundleID: bundleID,
      arguments: args, environment: env
    )
    if network {
      print("Launched \(bundleID) on \(device.name) (network diagnostics enabled)")
    }
  }
}
