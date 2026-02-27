import Foundation

/// A single element reference mapping a short ref ID to tap coordinates and metadata.
struct RefEntry: Codable {
  let ref: String         // "e1", "e2", ...
  let role: String        // "AXButton"
  let name: String        // "Sign In"
  let identifier: String
  let tapX: Int
  let tapY: Int
  let width: Int
  let height: Int
  let enabled: Bool
  let category: String    // "tab", "navigation", "action", "destructive", "disabled"
}

/// A snapshot of all element refs for the current screen, persisted between CLI invocations.
struct RefSnapshot: Codable {
  let fingerprint: String
  let screenName: String
  let interactiveCount: Int
  let elementCount: Int
  let timestamp: String
  let refs: [RefEntry]
}

/// Persistence layer for element refs — written by `explore`, consumed by `tap`.
enum RefStore {

  static var defaultPath: String {
    let dir = ProjectConfig.journalsDirectory()
    return (dir as NSString).appendingPathComponent("ref-store.json")
  }

  /// Save a ref snapshot to disk.
  static func save(_ snapshot: RefSnapshot) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(snapshot)
    let dir = (defaultPath as NSString).deletingLastPathComponent
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    try data.write(to: URL(fileURLWithPath: defaultPath))
  }

  /// Load the last saved ref snapshot.
  static func load() throws -> RefSnapshot {
    guard FileManager.default.fileExists(atPath: defaultPath) else {
      throw RefStoreError.noRefStore
    }
    let data = try Data(contentsOf: URL(fileURLWithPath: defaultPath))
    return try JSONDecoder().decode(RefSnapshot.self, from: data)
  }

  /// Resolve a ref string (e.g. "e3") to its entry.
  static func resolve(_ ref: String) throws -> RefEntry {
    let snapshot = try load()
    let normalized = ref.hasPrefix("@") ? String(ref.dropFirst()) : ref
    guard let entry = snapshot.refs.first(where: { $0.ref == normalized }) else {
      let available = snapshot.refs.map { "@\($0.ref)" }.joined(separator: ", ")
      throw RefStoreError.refNotFound(ref, available: available)
    }
    return entry
  }

  // MARK: - Build refs from ScreenAnalysis

  /// Assign sequential refs to all interactive elements from a screen analysis.
  /// Order: tabs → navigation → actions → destructive → disabled.
  static func buildRefs(from analysis: ScreenAnalysis) -> [RefEntry] {
    var refs: [RefEntry] = []
    var index = 1

    for tab in analysis.tabs {
      refs.append(RefEntry(
        ref: "e\(index)",
        role: "tab",
        name: tab.label,
        identifier: "",
        tapX: tab.tapX,
        tapY: tab.tapY,
        width: 60,
        height: 40,
        enabled: true,
        category: tab.isSelected ? "tab-selected" : "tab"
      ))
      index += 1
    }

    for el in analysis.navigation {
      refs.append(refEntry(from: el, index: index, category: "navigation"))
      index += 1
    }

    for el in analysis.actions {
      refs.append(refEntry(from: el, index: index, category: "action"))
      index += 1
    }

    for el in analysis.destructive {
      refs.append(refEntry(from: el, index: index, category: "destructive"))
      index += 1
    }

    for el in analysis.disabled {
      refs.append(refEntry(from: el, index: index, category: "disabled"))
      index += 1
    }

    return refs
  }

  private static func refEntry(
    from el: ScreenAnalysis.ClassifiedElement, index: Int, category: String
  ) -> RefEntry {
    RefEntry(
      ref: "e\(index)",
      role: el.role,
      name: el.name,
      identifier: el.identifier,
      tapX: el.tapX,
      tapY: el.tapY,
      width: el.width,
      height: el.height,
      enabled: category != "disabled",
      category: category
    )
  }
}

// MARK: - Role Abbreviations

extension RefEntry {
  /// Short role string for compact `explore -i` output.
  var shortRole: String {
    switch role {
    case "AXButton": return "btn"
    case "AXLink": return "link"
    case "AXTextField", "AXSecureTextField": return "field"
    case "AXCell": return "cell"
    case "AXSwitch", "AXToggle": return "switch"
    case "AXCheckBox": return "check"
    case "AXRadioButton": return "radio"
    case "AXSlider": return "slider"
    case "AXPopUpButton", "AXComboBox": return "select"
    case "AXSegmentedControl": return "segment"
    case "tab": return "tab"
    default:
      if category == "navigation" { return "nav" }
      return role.hasPrefix("AX") ? String(role.dropFirst(2)).lowercased() : role.lowercased()
    }
  }

  /// Suffix string for special states.
  var suffix: String {
    if category == "tab-selected" { return " (selected)" }
    if category == "destructive" { return " (destructive)" }
    if !enabled { return " (disabled)" }
    return ""
  }

  /// Formatted line for `explore -i` output.
  var interactiveLine: String {
    "@\(ref) [\(shortRole)] \"\(name)\"\(suffix)"
  }
}

// MARK: - Errors

enum RefStoreError: Error, LocalizedError {
  case noRefStore
  case refNotFound(String, available: String)

  var errorDescription: String? {
    switch self {
    case .noRefStore:
      return "No ref store. Run 'agent-sim explore -i' first."
    case .refNotFound(let ref, let available):
      return "@\(ref) not found. Available: \(available). Run 'agent-sim explore -i' to refresh."
    }
  }
}
