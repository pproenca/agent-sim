import Foundation

// MARK: - Element Model

struct AXNode: Sendable, Encodable {
  let role: String
  let label: String
  let identifier: String
  let value: String
  let roleDescription: String
  let accessibilityDescription: String
  let help: String
  let enabled: Bool
  let frame: Frame
  let depth: Int
  let children: [AXNode]

  struct Frame: Sendable, Encodable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    var centerX: Double { x + width / 2 }
    var centerY: Double { y + height / 2 }

    static let zero = Frame(x: 0, y: 0, width: 0, height: 0)

    func offsetBy(dx: Double, dy: Double) -> Frame {
      Frame(x: x - dx, y: y - dy, width: width, height: height)
    }
  }

  var isInteractive: Bool {
    ["AXButton", "AXLink", "AXTextField", "AXSecureTextField", "AXCell",
     "AXCheckBox", "AXRadioButton", "AXSlider", "AXSwitch", "AXToggle",
     "AXPopUpButton", "AXComboBox", "AXSegmentedControl", "AXTabGroup"]
      .contains(role)
  }

  var displayName: String {
    if !label.isEmpty { return label }
    if !accessibilityDescription.isEmpty { return accessibilityDescription }
    if !value.isEmpty { return value }
    if !identifier.isEmpty { return identifier }
    return role
  }
}

extension AXNode {
  /// Recursively flatten this node and all descendants into a flat array.
  func flattened() -> [AXNode] {
    var result = [self]
    for child in children { result.append(contentsOf: child.flattened()) }
    return result
  }
}

// MARK: - Tree Reader

enum AXTreeReader {

  /// Read the device's accessibility tree via FBAccessibilityCommands.
  /// Coordinates are native iOS device points — no transforms needed.
  static func readDeviceTree(simulatorUDID: String, maxDepth: Int = 20) async throws -> AXNode {
    let elements = try await AccessibilityFetcher.fetch(simulatorUDID: simulatorUDID)
    guard !elements.isEmpty else {
      throw DescribeError.noScreenContent
    }

    // The top-level array usually contains a single root element (the window/app).
    // If multiple roots, wrap them in a synthetic container.
    if elements.count == 1 {
      return convertElement(elements[0], depth: 0, maxDepth: maxDepth)
    }

    let children = elements.map { convertElement($0, depth: 1, maxDepth: maxDepth) }
    return AXNode(
      role: "AXGroup",
      label: "",
      identifier: "",
      value: "",
      roleDescription: "",
      accessibilityDescription: "",
      help: "",
      enabled: true,
      frame: .zero,
      depth: 0,
      children: children
    )
  }

  /// Collect all interactive elements from a tree.
  static func collectInteractive(_ node: AXNode) -> [AXNode] {
    node.flattened().filter(\.isInteractive)
  }

  /// Count elements by role.
  static func countByRole(_ node: AXNode) -> [String: Int] {
    var counts: [String: Int] = [node.role: 1]
    for child in node.children {
      for (role, count) in countByRole(child) {
        counts[role, default: 0] += count
      }
    }
    return counts
  }

  static func totalCount(_ node: AXNode) -> Int {
    1 + node.children.reduce(0) { $0 + totalCount($1) }
  }

  // MARK: - Private

  /// Map iOS accessibility type names to AX-prefixed role names.
  /// This ensures isInteractive, ScreenAnalyzer, and Fingerprinter all work unchanged.
  private static let roleMap: [String: String] = [
    "Button": "AXButton",
    "Link": "AXLink",
    "TextField": "AXTextField",
    "SecureTextField": "AXSecureTextField",
    "Cell": "AXCell",
    "CheckBox": "AXCheckBox",
    "RadioButton": "AXRadioButton",
    "Slider": "AXSlider",
    "Switch": "AXSwitch",
    "Toggle": "AXToggle",
    "PopUpButton": "AXPopUpButton",
    "ComboBox": "AXComboBox",
    "SegmentedControl": "AXSegmentedControl",
    "TabGroup": "AXTabGroup",
    "StaticText": "AXStaticText",
    "Image": "AXImage",
    "Group": "AXGroup",
    "ScrollView": "AXScrollArea",
    "Table": "AXTable",
    "NavigationBar": "AXNavigationBar",
    "TabBar": "AXTabGroup",
    "ToolBar": "AXToolbar",
    "Window": "AXWindow",
    "Application": "AXApplication",
    "Other": "AXGroup",
  ]

  private static func mapRole(_ type: String) -> String {
    roleMap[type] ?? "AX\(type)"
  }

  private static func convertElement(_ element: AccessibilityElement, depth: Int, maxDepth: Int) -> AXNode {
    let children: [AXNode]
    if depth < maxDepth, let elementChildren = element.children {
      children = elementChildren.map { convertElement($0, depth: depth + 1, maxDepth: maxDepth) }
    } else {
      children = []
    }

    let frame: AXNode.Frame
    if let f = element.frame {
      frame = AXNode.Frame(x: f.x, y: f.y, width: f.width, height: f.height)
    } else {
      frame = .zero
    }

    return AXNode(
      role: mapRole(element.type ?? "Other"),
      label: element.AXLabel ?? "",
      identifier: element.AXUniqueId ?? "",
      value: element.AXValue ?? "",
      roleDescription: "",
      accessibilityDescription: "",
      help: "",
      enabled: true,
      frame: frame,
      depth: depth,
      children: children
    )
  }
}
