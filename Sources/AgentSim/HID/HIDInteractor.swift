// Inlined from AXe (cameroncooke/AXe) — MIT License
import FBControlCore
import FBSimulatorControl
import Foundation
import ObjectiveC

/// HID touch/keyboard injection via Facebook IDB frameworks.
/// Provides the convenience API that SimulatorBridge expects.
enum HIDInteractor {

  /// Thread-safe mutable state — lock-protected, `Sendable` without `nonisolated(unsafe)`.
  private final class State: @unchecked Sendable {
    private let lock = NSLock()
    private var connections: [String: FBSimulatorHID] = [:]
    private var setUp = false

    var isSetUp: Bool {
      get { lock.withLock { setUp } }
      set { lock.withLock { setUp = newValue } }
    }

    func connection(for udid: String) -> FBSimulatorHID? {
      lock.withLock { connections[udid] }
    }

    func setConnection(_ hid: FBSimulatorHID, for udid: String) {
      lock.withLock { connections[udid] = hid }
    }
  }

  private static let state = State()

  private static var stabilizationDelayMs: UInt64 {
    if let envValue = ProcessInfo.processInfo.environment["AXE_HID_STABILIZATION_MS"],
       let milliseconds = UInt64(envValue)
    {
      return min(milliseconds, 1000)
    }
    return 25
  }

  // MARK: - Convenience API (used by SimulatorBridge)

  static func tap(x: Int, y: Int, simulatorID: String) async throws {
    try await ensureSetUp()
    let event = FBSimulatorHIDEvent.tapAt(x: Double(x), y: Double(y))
    try await performHIDEvent(event, simulatorID: simulatorID)
  }

  static func swipe(
    from start: (x: Int, y: Int),
    to end: (x: Int, y: Int),
    duration: Double,
    simulatorID: String
  ) async throws {
    try await ensureSetUp()
    let event = FBSimulatorHIDEvent.swipe(
      Double(start.x), yStart: Double(start.y),
      xEnd: Double(end.x), yEnd: Double(end.y),
      delta: 50, duration: duration
    )
    try await performHIDEvent(event, simulatorID: simulatorID)
  }

  static func type(_ text: String, simulatorID: String) async throws {
    try await ensureSetUp()
    let hidEvents = try TextToHIDEvents.convertTextToHIDEvents(text)
    for event in hidEvents {
      try await performHIDEvent(event, simulatorID: simulatorID)
    }
  }

  // MARK: - Core

  private static func performHIDEvent(_ event: FBSimulatorHIDEvent, simulatorID: String) async throws {
    let simulator = try SimulatorControlFactory.resolveSimulator(udid: simulatorID)
    let hid = try await getOrCreateHIDConnection(for: simulator)
    let future = event.perform(on: hid)
    _ = try await FutureBridge.value(future)

    if stabilizationDelayMs > 0 {
      try await Task.sleep(nanoseconds: stabilizationDelayMs * 1_000_000)
    }
  }

  private static func getOrCreateHIDConnection(for simulator: FBSimulator) async throws -> FBSimulatorHID {
    if let existing = state.connection(for: simulator.udid) {
      return existing
    }
    let hid = try await FutureBridge.value(simulator.connectToHID())
    state.setConnection(hid, for: simulator.udid)
    return hid
  }

  // MARK: - One-time setup

  static func ensureSetUp() async throws {
    guard !state.isSetUp else { return }

    let logger = FBControlCoreLoggerFactory.systemLoggerWriting(toStderr: false, withDebugLogging: false)

    // Verify Xcode
    let xcodePath = try await FutureBridge.value(FBXcodeDirectory.xcodeSelectDeveloperDirectory())
    guard xcodePath.length > 0 else {
      throw HIDError.xcodeNotAvailable
    }

    // Load private frameworks (SimulatorKit)
    try FBSimulatorControlFrameworkLoader.essentialFrameworks.loadPrivateFrameworks(logger)
    try FBSimulatorControlFrameworkLoader.xcodeFrameworks.loadPrivateFrameworks(logger)

    guard objc_lookUpClass("SimulatorKit.SimDeviceLegacyHIDClient") != nil else {
      throw HIDError.simulatorKitNotLoaded
    }

    state.isSetUp = true
  }

  // MARK: - Error

  enum HIDError: Error, CustomStringConvertible {
    case simulatorNotFound(String)
    case simulatorNotBooted(String)
    case xcodeNotAvailable
    case simulatorKitNotLoaded

    var description: String {
      switch self {
      case .simulatorNotFound(let udid): "Simulator \(udid) not found"
      case .simulatorNotBooted(let udid): "Simulator \(udid) is not booted"
      case .xcodeNotAvailable: "Xcode is not available (xcode-select)"
      case .simulatorKitNotLoaded: "SimulatorKit.SimDeviceLegacyHIDClient not found after framework load"
      }
    }
  }
}

