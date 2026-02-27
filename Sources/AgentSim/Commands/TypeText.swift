import ArgumentParser
import Foundation

struct TypeText: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "type",
    abstract: "Type text into the focused field on the simulator."
  )

  @Argument(help: "The text to type.")
  var text: String

  func run() async throws {
    let device = try await SimulatorBridge.resolveDevice()
    try await SimulatorBridge.type(text, simulatorID: device.udid)

    // Auto-log
    ActionLogger.log(ActionLogger.entry(action: "type", target: text))

    print("Done")
  }
}
