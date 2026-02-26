import ArgumentParser
import Foundation

struct Status: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Show simulator and accessibility status."
  )

  func run() async throws {
    let allDevices = (try? await SimulatorBridge.allBootedDevices()) ?? []

    print("Booted devices: \(allDevices.count)")
    for device in allDevices {
      print("  \(device.name)  \(device.udid)")
    }

    if let pinnedUDID = ProjectConfig.pinnedDeviceUDID() {
      if let match = allDevices.first(where: { $0.udid == pinnedUDID }) {
        print("Pinned: \(match.name)  \(match.udid)")
      } else {
        print("Pinned: \(pinnedUDID) (not currently booted)")
      }
    } else if allDevices.count > 1 {
      print("Pinned: none — run `agent-sim use` to pin")
    }

    if let device = try? await SimulatorBridge.resolveDevice() {
      print("Active device: \(device.name)")

      if let tree = try? await AXTreeReader.readDeviceTree(simulatorUDID: device.udid, maxDepth: 4) {
        let total = AXTreeReader.totalCount(tree)
        let interactive = AXTreeReader.collectInteractive(tree).count
        print("Screen elements: \(total) (\(interactive) interactive)")
      } else {
        print("Screen elements: could not read accessibility tree")
      }
    }
  }
}
