import ArgumentParser
import Foundation

struct Apps: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "List installed apps on the booted simulator."
  )

  @Flag(name: .long, help: "Include system apps (default: user-installed only).")
  var all = false

  @Flag(name: .long, help: "Show only currently running apps.")
  var running = false

  @Flag(name: .long, help: "Human-readable output instead of JSON.")
  var pretty = false

  func run() async throws {
    let device = try await SimulatorBridge.resolveDevice()

    if running {
      let runningApps = try await SimulatorBridge.runningApps(simulatorID: device.udid)
      if pretty {
        if runningApps.isEmpty {
          print("No running apps.")
        } else {
          print("Running apps on \(device.name):")
          for (bundleID, pid) in runningApps.sorted(by: { $0.key < $1.key }) {
            print("  \(bundleID)  (pid \(pid))")
          }
        }
      } else {
        JSONOutput.print(runningApps)
      }
      return
    }

    let apps = try await SimulatorBridge.installedApps(
      simulatorID: device.udid, userOnly: !all
    )

    if pretty {
      let label = all ? "All" : "User-installed"
      print("\(label) apps on \(device.name) (\(apps.count)):")
      for app in apps {
        print("  \(app.bundleID)  \(app.name)")
      }
    } else {
      JSONOutput.print(apps)
    }
  }
}
