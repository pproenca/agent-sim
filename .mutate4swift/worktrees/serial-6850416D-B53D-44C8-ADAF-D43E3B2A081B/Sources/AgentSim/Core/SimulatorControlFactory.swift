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

  /// Find a simulator by UDID regardless of boot state (for boot/install).
  static func findSimulator(udid: String) throws -> FBSimulator {
    let controlSet = try makeControl()
    guard let simulator = controlSet.set.allSimulators.first(where: { $0.udid == udid }) else {
      throw SimulatorBridge.SimError.commandFailed("Simulator \(udid) not found", 1)
    }
    return simulator
  }

  /// Find a shutdown simulator by name (or first available if name is nil).
  ///
  /// Match priority: exact name → shortest substring match.
  /// Warns to stderr when falling back to a fuzzy (substring) match.
  static func findShutdownSimulator(name: String?) throws -> FBSimulator {
    let controlSet = try makeControl()
    let shutdown = controlSet.set.allSimulators.filter { $0.state == .shutdown }

    if let name {
      // 1. Exact name match (case-insensitive)
      if let exact = shutdown.first(where: {
        $0.name.caseInsensitiveCompare(name) == .orderedSame
      }) {
        return exact
      }

      // 2. Substring match — prefer shortest name (most specific)
      let fuzzy = shutdown
        .filter { $0.name.localizedCaseInsensitiveContains(name) }
        .sorted { $0.name.count < $1.name.count }

      if let best = fuzzy.first {
        fputs("Note: No exact match for '\(name)'. Using '\(best.name)'.\n", stderr)
        return best
      }

      let available = shutdown.map(\.name).joined(separator: ", ")
      throw SimulatorBridge.SimError.commandFailed(
        "No shutdown simulator matching '\(name)'. Available: \(available)", 1
      )
    }

    guard let first = shutdown.first else {
      throw SimulatorBridge.SimError.commandFailed("No shutdown simulators available", 1)
    }
    return first
  }
}
