import ArgumentParser
import Foundation

struct Use: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Pin AgentSim to a specific simulator device. All commands will target this device."
  )

  @Argument(help: "Device name or UDID to pin to. Omit to show current pin.")
  var device: String?

  @Flag(name: .long, help: "Remove the device pin.")
  var clear = false

  func run() async throws {
    if clear {
      if ProjectConfig.unpinDevice() {
        print("Device pin removed.")
      } else {
        print("No device pin found.")
      }
      return
    }

    guard let query = device else {
      // Show current pin
      if let udid = ProjectConfig.pinnedDeviceUDID() {
        let all = (try? await SimulatorBridge.allBootedDevices()) ?? []
        if let match = all.first(where: { $0.udid == udid }) {
          print("Pinned: \(match.name)  \(match.udid)")
        } else {
          print("Pinned: \(udid) (not currently booted)")
        }
      } else {
        let all = (try? await SimulatorBridge.allBootedDevices()) ?? []
        print("No device pinned.")
        if all.count > 1 {
          print("Booted devices:")
          for d in all {
            print("  \(d.name)  \(d.udid)")
          }
          print("")
          print("Usage: agent-sim use \"\(all.first?.name ?? "iPhone 16")\"")
        }
      }
      return
    }

    // Resolve the device from booted simulators.
    // Priority: exact UDID → UDID prefix → exact name → name contains
    let all = try await SimulatorBridge.allBootedDevices()
    let match: SimulatorBridge.BootedDevice

    if let m = all.first(where: { $0.udid == query }) {
      match = m
    } else if let m = all.first(where: { $0.udid.hasPrefix(query) }) {
      match = m
    } else if let m = all.first(where: { $0.name.caseInsensitiveCompare(query) == .orderedSame }) {
      match = m
    } else if let m = all.first(where: { $0.name.localizedCaseInsensitiveContains(query) }) {
      match = m
    } else {
      throw DeviceResolutionError.deviceNotFound(query, available: all)
    }

    let path = try ProjectConfig.pinDevice(match.udid)
    print("Pinned to \(match.name) (\(match.udid))")
    print("Saved to \(path)")
  }
}
