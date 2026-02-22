import ArgumentParser
@preconcurrency import FBControlCore
import FBSimulatorControl
import Foundation

/// Bridges to FBSimulatorControl for all simulator operations.
/// Zero external commands — everything goes through the framework.
enum SimulatorBridge {

  // MARK: - Simulator Discovery

  struct BootedDevice: Sendable {
    let udid: String
    let name: String
    let screenWidthPoints: Double
    let screenHeightPoints: Double
  }

  /// List all booted simulators via FBSimulatorSet.
  static func allBootedDevices() async throws -> [BootedDevice] {
    let set = try await simulatorSet()
    return set.allSimulators
      .filter { $0.state == .booted }
      .map { sim in
        let (w, h) = screenSizePoints(from: sim)
        return BootedDevice(udid: sim.udid, name: sim.name, screenWidthPoints: w, screenHeightPoints: h)
      }
  }

  /// Resolve which booted simulator to use.
  ///
  /// Resolution order:
  /// 1. `.agent-sim/device` file (written by `agent-sim use`)
  /// 2. If exactly one simulator is booted, use it
  /// 3. If multiple are booted, error with `agent-sim use` hint
  static func resolveDevice() async throws -> BootedDevice {
    let all = try await allBootedDevices()

    if let pinnedUDID = ProjectConfig.pinnedDeviceUDID() {
      if let match = all.first(where: { $0.udid == pinnedUDID }) {
        return match
      }
      throw DeviceResolutionError.pinnedDeviceNotBooted(pinnedUDID, available: all)
    }

    switch all.count {
    case 0:
      throw DeviceResolutionError.noSimulator
    case 1:
      return all[0]
    default:
      throw DeviceResolutionError.multipleSimulators(all)
    }
  }

  /// Screen size in points, used by ScreenAnnotator for bounding box annotations.
  static func screenSize(for device: BootedDevice) -> (width: Double, height: Double) {
    (device.screenWidthPoints, device.screenHeightPoints)
  }

  // MARK: - Boot

  /// Boot a shutdown simulator. Waits until usable (AX-ready).
  static func boot(udid: String) async throws {
    try await HIDInteractor.ensureSetUp()
    let simulator = try SimulatorControlFactory.findSimulator(udid: udid)
    guard simulator.state != .booted else { return } // already booted
    let config = FBSimulatorBootConfiguration(
      options: .verifyUsable,
      environment: [:]
    )
    try await FutureBridge.value(simulator.boot(config))
  }

  /// Boot a shutdown simulator by name (or first available).
  static func bootByName(_ name: String?) async throws -> BootedDevice {
    try await HIDInteractor.ensureSetUp()
    let simulator = try SimulatorControlFactory.findShutdownSimulator(name: name)
    let config = FBSimulatorBootConfiguration(
      options: .verifyUsable,
      environment: [:]
    )
    try await FutureBridge.value(simulator.boot(config))
    let (w, h) = screenSizePoints(from: simulator)
    return BootedDevice(
      udid: simulator.udid, name: simulator.name,
      screenWidthPoints: w, screenHeightPoints: h
    )
  }

  // MARK: - App Install

  struct InstalledApp: Encodable {
    let bundleID: String
    let name: String
    let installType: String
  }

  /// Install a .app or .ipa onto the booted simulator. Returns bundle ID.
  static func install(simulatorID: String, appPath: String) async throws -> InstalledApp {
    let simulator = try await resolveSimulator(udid: simulatorID)
    let installed = try await FutureBridge.value(
      simulator.installApplication(withPath: appPath)
    )
    return InstalledApp(
      bundleID: installed.bundle.identifier,
      name: installed.bundle.name ?? installed.bundle.identifier,
      installType: "\(installed.installType)"
    )
  }

  /// List installed apps on the simulator.
  static func installedApps(simulatorID: String, userOnly: Bool) async throws -> [InstalledApp] {
    let simulator = try await resolveSimulator(udid: simulatorID)
    let apps = try await FutureBridge.value(simulator.installedApplications())
    let list = (apps as! [FBInstalledApplication])
    return list
      .filter { app in
        guard userOnly else { return true }
        let t = app.installType.rawValue
        return t == FBApplicationInstallType.user.rawValue
          || t == FBApplicationInstallType.userDevelopment.rawValue
          || t == FBApplicationInstallType.userEnterprise.rawValue
      }
      .map { app in
        InstalledApp(
          bundleID: app.bundle.identifier,
          name: app.bundle.name ?? app.bundle.identifier,
          installType: "\(app.installType)"
        )
      }
  }

  /// List running apps as bundle ID → PID.
  static func runningApps(simulatorID: String) async throws -> [String: Int] {
    let simulator = try await resolveSimulator(udid: simulatorID)
    let running = try await FutureBridge.value(simulator.runningApplications())
    var result: [String: Int] = [:]
    for (key, value) in running as! [String: NSNumber] {
      result[key] = value.intValue
    }
    return result
  }

  // MARK: - All Devices (any state)

  struct DeviceInfo: Encodable {
    let udid: String
    let name: String
    let state: String
    let screenWidthPoints: Double
    let screenHeightPoints: Double
  }

  /// List all simulators regardless of boot state.
  static func allDevices() async throws -> [DeviceInfo] {
    let set = try await simulatorSet()
    return set.allSimulators.map { sim in
      let (w, h) = screenSizePoints(from: sim)
      return DeviceInfo(
        udid: sim.udid, name: sim.name,
        state: "\(sim.state)",
        screenWidthPoints: w, screenHeightPoints: h
      )
    }
  }

  // MARK: - Screenshot

  static func screenshot(simulatorID: String, path: String) async throws -> String {
    let outputPath = path.isEmpty
      ? FileManager.default.temporaryDirectory.appendingPathComponent("agent-sim-\(UUID().uuidString).png").path
      : path
    let simulator = try await resolveSimulator(udid: simulatorID)
    let data = try await FutureBridge.value(simulator.takeScreenshot(.PNG))
    try (data as Data).write(to: URL(fileURLWithPath: outputPath))
    return outputPath
  }

  // MARK: - App Lifecycle

  static func launch(
    simulatorID: String, bundleID: String,
    arguments: [String] = [], environment: [String: String] = [:]
  ) async throws {
    let simulator = try await resolveSimulator(udid: simulatorID)
    let io = FBProcessIO<AnyObject, AnyObject, AnyObject>.outputToDevNull()
    let config = FBApplicationLaunchConfiguration(
      bundleID: bundleID,
      bundleName: nil,
      arguments: arguments,
      environment: environment,
      waitForDebugger: false,
      io: io,
      launchMode: .foregroundIfRunning
    )
    _ = try await FutureBridge.value(simulator.launchApplication(config))
  }

  static func terminate(simulatorID: String, bundleID: String) async throws {
    let simulator = try await resolveSimulator(udid: simulatorID)
    try await FutureBridge.value(simulator.killApplication(withBundleID: bundleID))
  }

  // MARK: - HID (tap + swipe + type)

  static func tap(x: Int, y: Int, simulatorID: String) async throws {
    try await HIDInteractor.tap(x: x, y: y, simulatorID: simulatorID)
  }

  static func swipe(
    direction: SwipeDirection, simulatorID: String,
    duration: Double = 0.5, delta: Int = 300
  ) async throws {
    let device = try await resolveDevice()
    let (x1, y1, x2, y2) = direction.coordinates(
      delta: delta,
      screenWidth: Int(device.screenWidthPoints),
      screenHeight: Int(device.screenHeightPoints)
    )
    try await HIDInteractor.swipe(
      from: (x: x1, y: y1),
      to: (x: x2, y: y2),
      duration: duration,
      simulatorID: simulatorID
    )
  }

  static func swipe(
    from start: (x: Int, y: Int),
    to end: (x: Int, y: Int),
    duration: Double,
    simulatorID: String
  ) async throws {
    try await HIDInteractor.swipe(
      from: start, to: end,
      duration: duration,
      simulatorID: simulatorID
    )
  }

  static func type(_ text: String, simulatorID: String) async throws {
    try await HIDInteractor.type(text, simulatorID: simulatorID)
  }

  enum SwipeDirection: String, Sendable, CaseIterable, ExpressibleByArgument {
    case up, down, left, right

    func coordinates(
      delta: Int,
      screenWidth: Int = DeviceConstants.defaultWidth,
      screenHeight: Int = DeviceConstants.defaultHeight
    ) -> (Int, Int, Int, Int) {
      let cx = screenWidth / 2
      let cy = screenHeight / 2
      switch self {
      case .up: return (cx, cy + delta / 2, cx, cy - delta / 2)
      case .down: return (cx, cy - delta / 2, cx, cy + delta / 2)
      case .left: return (cx + delta / 2, cy, cx - delta / 2, cy)
      case .right: return (cx - delta / 2, cy, cx + delta / 2, cy)
      }
    }
  }

  // MARK: - Log Queries (via FBProcessSpawnCommands — spawns `log` inside the simulator)

  static func queryLogs(
    simulatorID: String, processName: String, subsystem: String?, lastSeconds: Int
  ) async throws -> String {
    let safeName = processName.replacingOccurrences(of: "'", with: "")
    var predicate = "process == '\(safeName)'"
    if let sub = subsystem {
      let safeSub = sub.replacingOccurrences(of: "'", with: "")
      predicate += " AND subsystem == '\(safeSub)'"
    }

    let simulator = try await resolveSimulator(udid: simulatorID)
    let io = FBProcessIO<AnyObject, AnyObject, AnyObject>.outputToDevNull()
    let config = FBProcessSpawnConfiguration(
      launchPath: "/usr/bin/log",
      arguments: [
        "show",
        "--predicate", predicate,
        "--last", "\(lastSeconds)s",
        "--style", "ndjson",
      ],
      environment: [:],
      io: io,
      mode: .default
    )
    let result = try await FutureBridge.value(
      FBProcessSpawnCommandHelpers.launchConsumingStdout(config, with: simulator)
    )
    return result as String
  }

  // MARK: - Internal

  private static func resolveSimulator(udid: String) async throws -> FBSimulator {
    try await HIDInteractor.ensureSetUp()
    return try SimulatorControlFactory.resolveSimulator(udid: udid)
  }

  private static func simulatorSet() async throws -> FBSimulatorSet {
    try await HIDInteractor.ensureSetUp()
    return try SimulatorControlFactory.makeControl().set
  }

  /// Compute screen size in points from FBSimulator's screenInfo.
  /// Falls back to 393x852 (iPhone 16) if screenInfo is unavailable, with a stderr warning.
  private static func screenSizePoints(from simulator: FBSimulator) -> (Double, Double) {
    guard let info = simulator.screenInfo, info.scale > 0 else {
      fputs(
        "warning: Could not detect screen size for \(simulator.name) (\(simulator.udid)). "
        + "Falling back to iPhone 16 (\(DeviceConstants.defaultWidth)x\(DeviceConstants.defaultHeight)). "
        + "Coordinates may be wrong if this is a different device type.\n",
        stderr
      )
      return (Double(DeviceConstants.defaultWidth), Double(DeviceConstants.defaultHeight))
    }
    return (Double(info.widthPixels) / Double(info.scale), Double(info.heightPixels) / Double(info.scale))
  }

  enum SimError: Error, LocalizedError {
    case commandFailed(String, Int)

    var errorDescription: String? {
      switch self {
      case .commandFailed(let cmd, let code):
        "Command failed (exit \(code)): \(cmd)"
      }
    }
  }
}

enum DeviceResolutionError: Error, LocalizedError {
  case noSimulator
  case multipleSimulators([SimulatorBridge.BootedDevice])
  case deviceNotFound(String, available: [SimulatorBridge.BootedDevice])
  case pinnedDeviceNotBooted(String, available: [SimulatorBridge.BootedDevice])

  var errorDescription: String? {
    switch self {
    case .noSimulator:
      "No booted iOS Simulator found. Run: agent-sim boot"
    case .multipleSimulators(let devices):
      """
      Multiple simulators are booted. Pin one with:

      \(devices.map { "  agent-sim use \"\($0.name)\"" }.joined(separator: "\n"))
      """
    case .deviceNotFound(let query, let available):
      """
      No booted device matches "\(query)".
      Available:
      \(available.map { "  \($0.name)  \($0.udid)" }.joined(separator: "\n"))
      """
    case .pinnedDeviceNotBooted(let udid, let available):
      """
      Pinned device \(udid) is not currently booted.
      Boot it: agent-sim boot --udid \(udid)
      Or clear: agent-sim use --clear
      \(available.isEmpty ? "" : "Booted:\n\(available.map { "  \($0.name)  \($0.udid)" }.joined(separator: "\n"))")
      """
    }
  }
}
