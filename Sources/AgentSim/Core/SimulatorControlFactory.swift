@preconcurrency import FBControlCore
import FBSimulatorControl
import Foundation

/// Centralized factory for FBSimulatorControl configuration.
/// Eliminates repeated logger/reporter/config creation across HIDInteractor,
/// SimulatorBridge, and AccessibilityFetcher.
enum SimulatorControlFactory {
  /// Create a FBSimulatorControl instance with standard configuration.
  static func makeControl() throws -> FBSimulatorControl {
    let logger = FBControlCoreLoggerFactory.systemLoggerWriting(toStderr: false, withDebugLogging: false)
    let reporter = FBEmptyEventReporter.shared
    let config = FBSimulatorControlConfiguration(deviceSetPath: nil, logger: logger, reporter: reporter)
    return try FBSimulatorControl.withConfiguration(config)
  }

  /// Resolve a specific booted simulator by UDID.
  static func resolveSimulator(udid: String) throws -> FBSimulator {
    let controlSet = try makeControl()
    guard let simulator = controlSet.set.allSimulators.first(where: { $0.udid == udid }) else {
      throw SimulatorBridge.SimError.commandFailed("Simulator \(udid) not found", 1)
    }
    guard simulator.state == .booted else {
      throw SimulatorBridge.SimError.commandFailed("Simulator \(udid) is not booted", 1)
    }
    return simulator
  }
}
