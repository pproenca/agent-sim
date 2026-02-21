import ArgumentParser
import Foundation

struct FingerprintCmd: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "fingerprint",
    abstract: "Compute a stable fingerprint for the current screen. Use to detect screen transitions."
  )

  @Flag(name: .long, help: "Output only the hash, no screen name.")
  var hashOnly = false

  func run() async throws {
    let device = try await SimulatorBridge.resolveDevice()
    let simNode = try await AXTreeReader.readDeviceTree(simulatorUDID: device.udid)
    let hash = Fingerprinter.fingerprint(simNode)

    if hashOnly {
      print(hash)
    } else {
      let analysis = ScreenAnalyzer.analyze(simNode)
      print("\(hash) \(analysis.screenName)")
    }
  }
}
