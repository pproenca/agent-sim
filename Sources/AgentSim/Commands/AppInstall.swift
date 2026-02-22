import ArgumentParser
import Foundation

struct AppInstall: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "install",
    abstract: "Install a .app or .ipa onto the booted simulator."
  )

  @Argument(help: "Path to the .app bundle or .ipa file.")
  var path: String

  func run() async throws {
    let resolved = (path as NSString).standardizingPath
    guard FileManager.default.fileExists(atPath: resolved) else {
      throw InstallError.fileNotFound(resolved)
    }

    let device = try await SimulatorBridge.resolveDevice()
    let app = try await SimulatorBridge.install(
      simulatorID: device.udid, appPath: resolved
    )

    let output = InstallOutput(
      bundleID: app.bundleID,
      name: app.name,
      simulator: device.name,
      path: resolved
    )
    JSONOutput.print(output)
  }
}

private struct InstallOutput: Encodable {
  let bundleID: String
  let name: String
  let simulator: String
  let path: String
}

enum InstallError: Error, LocalizedError {
  case fileNotFound(String)

  var errorDescription: String? {
    switch self {
    case .fileNotFound(let path):
      "File not found: \(path)"
    }
  }
}
