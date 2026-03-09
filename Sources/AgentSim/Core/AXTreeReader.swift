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

    /// Returns true if `other`'s center point falls within this frame.
    func containsCenter(of other: Frame) -> Bool {
      let cx = other.centerX
      let cy = other.centerY
      return cx >= x && cx <= x + width && cy >= y && cy <= y + height
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
  /// Coordinates are normalized to iOS device points.
  ///
  /// Some apps (notably some Expo/React Native builds) expose AX frames in
  /// simulator-window/absolute coordinates instead of device points. We detect
  /// the top-level viewport frame and normalize all node frames into device space.
  static func readDeviceTree(simulatorUDID: String, maxDepth: Int = 20) async throws -> AXNode {
    let elements = try await AccessibilityFetcher.fetch(simulatorUDID: simulatorUDID)
    guard !elements.isEmpty else {
      throw ReadError.noScreenContent
    }

    // The top-level array usually contains a single root element (the window/app).
    // If multiple roots, wrap them in a synthetic container.
    let rawTree: AXNode
    if elements.count == 1 {
      rawTree = convertElement(elements[0], depth: 0, maxDepth: maxDepth)
    } else {
      let children = elements.map { convertElement($0, depth: 1, maxDepth: maxDepth) }
      rawTree = AXNode(
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

    let device = try await SimulatorBridge.resolveDevice(udid: simulatorUDID)
    return normalizeToDevicePoints(
      rawTree,
      deviceWidth: device.screenWidthPoints,
      deviceHeight: device.screenHeightPoints
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

  // MARK: - Coordinate Normalization

  /// Normalize a raw AX tree into simulator device-point coordinates.
  /// This is a no-op when the tree already matches the device coordinate space.
  static func normalizeToDevicePoints(
    _ root: AXNode,
    deviceWidth: Double,
    deviceHeight: Double
  ) -> AXNode {
    guard let viewport = inferredViewportFrame(from: root) else {
      return root
    }

    guard shouldNormalize(viewport: viewport, deviceWidth: deviceWidth, deviceHeight: deviceHeight) else {
      return root
    }

    let scaleX = deviceWidth / viewport.width
    let scaleY = deviceHeight / viewport.height

    if ProcessInfo.processInfo.environment["AGENT_SIM_DEBUG_COORDS"] == "1" {
      fputs(
        "info: Normalizing AX coordinates using viewport "
        + "x=\(viewport.x), y=\(viewport.y), w=\(viewport.width), h=\(viewport.height); "
        + "scaleX=\(scaleX), scaleY=\(scaleY)\n",
        stderr
      )
    }

    return mapFrames(root) { frame in
      guard frame.width > 0 || frame.height > 0 else {
        return frame
      }
      return AXNode.Frame(
        x: (frame.x - viewport.x) * scaleX,
        y: (frame.y - viewport.y) * scaleY,
        width: frame.width * scaleX,
        height: frame.height * scaleY
      )
    }
  }

  /// Infer the top-level viewport frame that the AX coordinates are relative to.
  /// Prefers shallow `AXWindow`/`AXApplication` containers over deep content nodes.
  static func inferredViewportFrame(from root: AXNode) -> AXNode.Frame? {
    let candidates = root.flattened().filter {
      $0.depth <= 2 && $0.frame.width > 100 && $0.frame.height > 100
    }
    guard !candidates.isEmpty else { return nil }

    return candidates
      .sorted {
        let lhsRole = viewportRolePriority($0.role)
        let rhsRole = viewportRolePriority($1.role)
        if lhsRole != rhsRole { return lhsRole > rhsRole }
        return ($0.frame.width * $0.frame.height) > ($1.frame.width * $1.frame.height)
      }
      .first?
      .frame
  }

  private static func shouldNormalize(
    viewport: AXNode.Frame,
    deviceWidth: Double,
    deviceHeight: Double
  ) -> Bool {
    guard viewport.width > 0, viewport.height > 0 else { return false }
    let scaleX = deviceWidth / viewport.width
    let scaleY = deviceHeight / viewport.height
    let originMismatch = abs(viewport.x) > 1 || abs(viewport.y) > 1
    let scaleMismatch = abs(scaleX - 1) > 0.03 || abs(scaleY - 1) > 0.03
    return originMismatch || scaleMismatch
  }

  private static func viewportRolePriority(_ role: String) -> Int {
    switch role {
    case "AXWindow":
      return 3
    case "AXApplication":
      return 2
    case "AXGroup":
      return 1
    default:
      return 0
    }
  }

  private static func mapFrames(_ node: AXNode, transform: (AXNode.Frame) -> AXNode.Frame) -> AXNode {
    let mappedChildren = node.children.map { mapFrames($0, transform: transform) }
    return AXNode(
      role: node.role,
      label: node.label,
      identifier: node.identifier,
      value: node.value,
      roleDescription: node.roleDescription,
      accessibilityDescription: node.accessibilityDescription,
      help: node.help,
      enabled: node.enabled,
      frame: transform(node.frame),
      depth: node.depth,
      children: mappedChildren
    )
  }

  // MARK: - Errors

  enum ReadError: Error, LocalizedError {
    case noScreenContent

    var errorDescription: String? {
      switch self {
      case .noScreenContent:
        "Could not find iOS app content in the Simulator's accessibility tree."
      }
    }
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
