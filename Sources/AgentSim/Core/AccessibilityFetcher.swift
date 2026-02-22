// Adapted from AXe (cameroncooke/AXe) — MIT License
import FBControlCore
import FBSimulatorControl
import Foundation

// MARK: - Element Model (matches FBAccessibilityCommands nested JSON)

struct AccessibilityElement: Decodable, Sendable {
  let type: String?
  let frame: ElementFrame?
  let children: [AccessibilityElement]?
  let AXLabel: String?
  let AXUniqueId: String?
  let AXValue: String?

  struct ElementFrame: Decodable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
  }

  enum CodingKeys: String, CodingKey {
    case type, frame, children
    case AXLabel, AXUniqueId, AXValue
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    type = try container.decodeIfPresent(String.self, forKey: .type)
    frame = try container.decodeIfPresent(ElementFrame.self, forKey: .frame)
    children = try container.decodeIfPresent([AccessibilityElement].self, forKey: .children)
    AXLabel = try container.decodeIfPresent(String.self, forKey: .AXLabel)
    AXUniqueId = try container.decodeIfPresent(String.self, forKey: .AXUniqueId)
    AXValue = try container.decodeIfPresent(String.self, forKey: .AXValue)
  }
}

// MARK: - Fetcher

enum AccessibilityFetcher {

  /// Fetch the accessibility tree from the iOS simulator via FBAccessibilityCommands.
  /// Returns native iOS device-point coordinates — no transforms needed.
  static func fetch(simulatorUDID: String) async throws -> [AccessibilityElement] {
    try await HIDInteractor.ensureSetUp()
    let simulator = try SimulatorControlFactory.resolveSimulator(udid: simulatorUDID)

    let future: FBFuture<AnyObject> = simulator.accessibilityElements(withNestedFormat: true)
    let result = try await FutureBridge.value(future)

    let jsonData = try JSONSerialization.data(withJSONObject: result, options: [])
    return try JSONDecoder().decode([AccessibilityElement].self, from: jsonData)
  }

  enum AccessibilityFetchError: Error, CustomStringConvertible {
    case simulatorNotFound(String)
    case simulatorNotBooted(String)

    var description: String {
      switch self {
      case .simulatorNotFound(let udid): "Simulator \(udid) not found"
      case .simulatorNotBooted(let udid): "Simulator \(udid) is not booted"
      }
    }
  }
}

// MARK: - Shared empty reporter (reuses HIDInteractor's pattern)

@objc final class FBEmptyEventReporter: NSObject, FBEventReporter, @unchecked Sendable {
  static let shared = FBEmptyEventReporter()
  var metadata: [String: String] = [:]
  func report(_ subject: FBEventReporterSubject) {}
  func addMetadata(_ metadata: [String: String]) {}
}
