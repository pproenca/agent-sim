import ArgumentParser
import Foundation

struct SimGroup: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "sim",
    abstract: "Simulator management: boot, list, shutdown, install apps.",
    subcommands: [
      SimBoot.self,
      SimList.self,
      SimShutdown.self,
      SimInstall.self,
      SimApps.self,
    ]
  )
}

// MARK: - sim boot

struct SimBoot: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "boot",
    abstract: "Boot a simulator. Waits until fully usable before returning."
  )

  @Argument(help: "Simulator name (e.g. 'iPhone 16'). Boots first available if omitted.")
  var name: String?

  @Option(name: .long, help: "Boot a specific simulator by UDID.")
  var udid: String?

  func run() async throws {
    let device: SimulatorBridge.BootedDevice
    if let udid {
      try await SimulatorBridge.boot(udid: udid)
      device = try await SimulatorBridge.resolveDevice()
    } else {
      device = try await SimulatorBridge.bootByName(name)
    }

    try ProjectConfig.pinDevice(device.udid)
    let shortUDID = String(device.udid.prefix(8))
    fputs("Pinned to \(device.name) (\(shortUDID))\n", stderr)

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

// MARK: - sim list

struct SimList: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: "List simulators. Shows shutdown simulators by default."
  )

  @Flag(name: .long, help: "Show all simulators regardless of state.")
  var all = false

  @Flag(name: .long, help: "Show only booted simulators.")
  var booted = false

  func run() async throws {
    let devices = try await SimulatorBridge.allDevices()

    let filtered: [SimulatorBridge.DeviceInfo]
    if all {
      filtered = devices
    } else if booted {
      filtered = devices.filter {
        $0.state.lowercased().contains("booted")
      }
    } else {
      filtered = devices.filter {
        $0.state.lowercased().contains("shutdown")
      }
    }

    if filtered.isEmpty {
      let label = all ? "" : booted ? " booted" : " shutdown"
      fputs("No\(label) simulators found.\n", stderr)
      return
    }

    JSONOutput.print(filtered)
  }
}

// MARK: - sim shutdown

struct SimShutdown: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "shutdown",
    abstract: "Shut down a booted simulator."
  )

  @Argument(help: "Simulator name or UDID. Shuts down the pinned/only booted simulator if omitted.")
  var nameOrUDID: String?

  func run() async throws {
    let device: SimulatorBridge.BootedDevice

    if let nameOrUDID {
      // Try as UDID first, then as name
      let allBooted = try await SimulatorBridge.allBootedDevices()
      if let byUDID = allBooted.first(where: { $0.udid == nameOrUDID }) {
        device = byUDID
      } else if let byName = allBooted.first(where: {
        $0.name.caseInsensitiveCompare(nameOrUDID) == .orderedSame
      }) {
        device = byName
      } else if let fuzzy = allBooted.first(where: {
        $0.name.localizedCaseInsensitiveContains(nameOrUDID)
      }) {
        fputs("Note: No exact match for '\(nameOrUDID)'. Using '\(fuzzy.name)'.\n", stderr)
        device = fuzzy
      } else {
        let available = allBooted.map { "\($0.name) (\($0.udid))" }.joined(separator: ", ")
        throw SimulatorBridge.SimError.commandFailed(
          "No booted simulator matching '\(nameOrUDID)'. Booted: \(available)", 1
        )
      }
    } else {
      device = try await SimulatorBridge.resolveDevice()
    }

    try await SimulatorBridge.shutdown(udid: device.udid)
    fputs("Shut down \(device.name) (\(device.udid))\n", stderr)

    let output = ShutdownOutput(status: "shutdown", udid: device.udid, name: device.name)
    JSONOutput.print(output)
  }
}

private struct ShutdownOutput: Encodable {
  let status: String
  let udid: String
  let name: String
}

// MARK: - sim install

struct SimInstall: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "install",
    abstract: "Install a .app or .ipa onto the booted simulator."
  )

  @Argument(help: "Path to the .app bundle or .ipa file.")
  var path: String

  @Option(name: .long, help: "Target a specific simulator by UDID, bypassing the device pin.")
  var udid: String?

  func run() async throws {
    let resolved = (path as NSString).standardizingPath
    guard FileManager.default.fileExists(atPath: resolved) else {
      throw InstallError.fileNotFound(resolved)
    }

    let device = try await SimulatorBridge.resolveDevice(udid: udid)
    let app = try await SimulatorBridge.install(
      simulatorID: device.udid, appPath: resolved
    )

    let output = SimInstallOutput(
      bundleID: app.bundleID,
      name: app.name,
      simulator: device.name,
      path: resolved
    )
    JSONOutput.print(output)
  }
}

private struct SimInstallOutput: Encodable {
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

// MARK: - sim apps

struct SimApps: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "apps",
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
