import ArgumentParser
import Foundation

struct Screenshot: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Capture a screenshot of the simulator."
  )

  @Argument(help: "Output path for the PNG file. Defaults to a temp file.")
  var path: String?

  func run() async throws {
    let device = try await SimulatorBridge.resolveDevice()
    let outputPath = try await SimulatorBridge.screenshot(simulatorID: device.udid, path: path ?? "")
    print(outputPath)
  }
}
