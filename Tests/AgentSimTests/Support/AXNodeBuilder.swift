/// Convenience builders for constructing AXNode trees in tests.
/// Usage:
///   let button = AXNodeBuilder.button("Sign In", at: (196, 426), size: (120, 44))
///   let screen = AXNodeBuilder.screen(children: [button])
@testable import AgentSimLib

enum AXNodeBuilder {

  // MARK: - Leaf Nodes

  static func node(
    role: String = "AXGroup",
    label: String = "",
    identifier: String = "",
    value: String = "",
    enabled: Bool = true,
    x: Double = 0, y: Double = 0,
    width: Double = 0, height: Double = 0,
    depth: Int = 0,
    children: [AXNode] = []
  ) -> AXNode {
    AXNode(
      role: role,
      label: label,
      identifier: identifier,
      value: value,
      roleDescription: "",
      accessibilityDescription: "",
      help: "",
      enabled: enabled,
      frame: .init(x: x, y: y, width: width, height: height),
      depth: depth,
      children: children
    )
  }

  static func button(
    _ label: String,
    at center: (Double, Double),
    size: (Double, Double) = (100, 44),
    identifier: String = "",
    enabled: Bool = true,
    depth: Int = 3
  ) -> AXNode {
    node(
      role: "AXButton",
      label: label,
      identifier: identifier,
      enabled: enabled,
      x: center.0 - size.0 / 2,
      y: center.1 - size.1 / 2,
      width: size.0,
      height: size.1,
      depth: depth
    )
  }

  static func text(
    _ content: String,
    at position: (Double, Double),
    size: (Double, Double) = (200, 20),
    depth: Int = 3
  ) -> AXNode {
    node(
      role: "AXStaticText",
      label: content,
      x: position.0, y: position.1,
      width: size.0, height: size.1,
      depth: depth
    )
  }

  static func link(
    _ label: String,
    at center: (Double, Double),
    size: (Double, Double) = (100, 44),
    depth: Int = 3
  ) -> AXNode {
    node(
      role: "AXLink",
      label: label,
      x: center.0 - size.0 / 2,
      y: center.1 - size.1 / 2,
      width: size.0,
      height: size.1,
      depth: depth
    )
  }

  static func textField(
    _ label: String = "",
    identifier: String = "",
    at center: (Double, Double),
    size: (Double, Double) = (300, 44),
    depth: Int = 3
  ) -> AXNode {
    node(
      role: "AXTextField",
      label: label,
      identifier: identifier,
      x: center.0 - size.0 / 2,
      y: center.1 - size.1 / 2,
      width: size.0,
      height: size.1,
      depth: depth
    )
  }

  static func cell(
    _ label: String,
    at center: (Double, Double),
    size: (Double, Double) = (393, 60),
    depth: Int = 3
  ) -> AXNode {
    node(
      role: "AXCell",
      label: label,
      x: center.0 - size.0 / 2,
      y: center.1 - size.1 / 2,
      width: size.0,
      height: size.1,
      depth: depth
    )
  }

  // MARK: - Compound Nodes

  /// Simulates the AXGroup that wraps iOS app content in the Simulator.
  /// This is what `findScreenContent` looks for.
  static func screenContent(
    origin: (Double, Double) = (0, 0),
    size: (Double, Double) = (393, 852),
    depth: Int = 2,
    children: [AXNode] = []
  ) -> AXNode {
    node(
      role: "AXGroup",
      x: origin.0, y: origin.1,
      width: size.0, height: size.1,
      depth: depth,
      children: children
    )
  }

  /// Simulates a full Simulator AX tree: AXApplication > AXWindow > AXGroup (screen content).
  static func simulatorTree(
    windowLabel: String = "iPhone 16",
    windowOrigin: (Double, Double) = (100, 200),
    windowSize: (Double, Double) = (359, 778),
    screenChildren: [AXNode] = []
  ) -> AXNode {
    let screen = screenContent(
      origin: windowOrigin,
      size: windowSize,
      depth: 2,
      children: screenChildren
    )
    let window = node(
      role: "AXWindow",
      label: windowLabel,
      x: windowOrigin.0, y: windowOrigin.1,
      width: windowSize.0, height: windowSize.1,
      depth: 1,
      children: [screen]
    )
    return node(
      role: "AXApplication",
      label: "Simulator",
      depth: 0,
      children: [window]
    )
  }

  /// A tab group with named tabs.
  static func tabGroup(
    tabs: [(label: String, selected: Bool)],
    y: Double = 808,
    depth: Int = 3
  ) -> AXNode {
    let tabWidth = 80.0
    let children = tabs.enumerated().map { index, tab in
      node(
        role: "AXButton",
        label: tab.label,
        value: tab.selected ? "1" : "0",
        x: Double(index) * tabWidth + 20,
        y: y,
        width: tabWidth,
        height: 44,
        depth: depth + 1
      )
    }
    return node(
      role: "AXTabGroup",
      x: 0, y: y,
      width: 393, height: 44,
      depth: depth,
      children: children
    )
  }
}
