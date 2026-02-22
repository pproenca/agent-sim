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
    let (x1, y1, x2, y2) = direction.coordinates(delta: delta)
    try await HIDInteractor.swipe(
      from: (x: x1, y: y1),
      to: (x: x2, y: y2),
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
  /// Falls back to 393x852 (iPhone 16) if screenInfo is unavailable.
  private static func screenSizePoints(from simulator: FBSimulator) -> (Double, Double) {
    guard let info = simulator.screenInfo, info.scale > 0 else {
      return (Double(DeviceConstants.defaultWidth), Double(DeviceConstants.defaultHeight))
    }
    return (Double(info.widthPixels) / Double(info.scale), Double(info.heightPixels) / Double(info.scale))
  }

  enum SimError: Error, CustomStringConvertible {
    case commandFailed(String, Int)

    var description: String {
      switch self {
      case .commandFailed(let cmd, let code):
        "Command failed (exit \(code)): \(cmd)"
      }
    }
  }
}

enum DeviceResolutionError: Error, CustomStringConvertible {
  case noSimulator
  case multipleSimulators([SimulatorBridge.BootedDevice])
  case deviceNotFound(String, available: [SimulatorBridge.BootedDevice])
  case pinnedDeviceNotBooted(String, available: [SimulatorBridge.BootedDevice])

  var description: String {
    switch self {
    case .noSimulator:
      "No booted iOS Simulator found."
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
      Clear with: agent-sim use --clear
      \(available.isEmpty ? "" : "Booted:\n\(available.map { "  \($0.name)  \($0.udid)" }.joined(separator: "\n"))")
      """
    }
  }
}
