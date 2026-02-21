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

  @Flag(name: .long, help: "Enable CFNetwork HTTP diagnostics for agent-sim network.")
  var network = false

  func run() async throws {
    let device = try await SimulatorBridge.resolveDevice()
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

struct Terminate: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Terminate a running app on the booted simulator."
  )

  @Argument(help: "Bundle identifier of the app to terminate.")
  var bundleID: String

  func run() async throws {
    let device = try await SimulatorBridge.resolveDevice()
    try await SimulatorBridge.terminate(simulatorID: device.udid, bundleID: bundleID)
  }
}
