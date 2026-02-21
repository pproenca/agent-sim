import Testing
@testable import AgentSimLib

@Suite("Coordinate transforms — forward pipeline (AX → device space)")
struct CoordinateTransformTests {

  // MARK: - toSimulatorCoordinates

  @Test("toSimulatorCoordinates subtracts origin from position")
  func subtractsOrigin() {
    let node = AXNodeBuilder.button("OK", at: (250, 500))
    let origin = AXNode.Frame(x: 100, y: 200, width: 393, height: 852)

    let result = AXTreeReader.toSimulatorCoordinates(node, origin: origin)

    // Button center was at (250, 500) absolute → (150, 300) relative
    // Frame x was at 250-50=200 absolute → 100 relative
    #expect(result.frame.x == 200 - 100)
    #expect(result.frame.y == 500 - 22 - 200) // center.y - halfHeight - origin.y
  }

  @Test("toSimulatorCoordinates preserves size")
  func preservesSize() {
    let node = AXNodeBuilder.button("OK", at: (250, 500), size: (120, 44))
    let origin = AXNode.Frame(x: 100, y: 200, width: 393, height: 852)

    let result = AXTreeReader.toSimulatorCoordinates(node, origin: origin)

    #expect(result.frame.width == 120)
    #expect(result.frame.height == 44)
  }

  @Test("toSimulatorCoordinates recurses into children")
  func recursesChildren() {
    let child = AXNodeBuilder.button("Child", at: (300, 600))
    let parent = AXNodeBuilder.node(
      role: "AXGroup",
      x: 100, y: 200, width: 393, height: 852,
      children: [child]
    )
    let origin = AXNode.Frame(x: 100, y: 200, width: 393, height: 852)

    let result = AXTreeReader.toSimulatorCoordinates(parent, origin: origin)

    #expect(result.children.count == 1)
    let childResult = result.children[0]
    // Child button center was at (300, 600), so frame.x = 300 - 50 = 250
    // After offsetBy(dx: 100): 250 - 100 = 150
    #expect(childResult.frame.x == 250 - 100)
  }

  @Test("toSimulatorCoordinates preserves non-spatial properties")
  func preservesProperties() {
    let node = AXNodeBuilder.node(
      role: "AXButton",
      label: "Submit",
      identifier: "submit_btn",
      value: "enabled",
      enabled: true,
      x: 200, y: 300, width: 100, height: 44,
      depth: 3
    )
    let origin = AXNode.Frame(x: 50, y: 50, width: 393, height: 852)

    let result = AXTreeReader.toSimulatorCoordinates(node, origin: origin)

    #expect(result.role == "AXButton")
    #expect(result.label == "Submit")
    #expect(result.identifier == "submit_btn")
    #expect(result.value == "enabled")
    #expect(result.enabled == true)
    #expect(result.depth == 3)
  }

  // MARK: - scaleToDevice

  @Test("scaleToDevice multiplies all frame properties by scale factors")
  func scalesFrame() {
    // Window is 359×778, device is 393×852 → scaleX ≈ 1.0947, scaleY ≈ 1.0951
    let scaleX = 393.0 / 359.0
    let scaleY = 852.0 / 778.0

    let node = AXNodeBuilder.button("OK", at: (180, 400), size: (100, 44))
    let result = AXTreeReader.scaleToDevice(node, scaleX: scaleX, scaleY: scaleY)

    // Frame x was 180 - 50 = 130. Scaled: 130 * scaleX
    let expectedX = 130.0 * scaleX
    let expectedY = (400.0 - 22.0) * scaleY
    let expectedW = 100.0 * scaleX
    let expectedH = 44.0 * scaleY

    #expect(abs(result.frame.x - expectedX) < 0.01)
    #expect(abs(result.frame.y - expectedY) < 0.01)
    #expect(abs(result.frame.width - expectedW) < 0.01)
    #expect(abs(result.frame.height - expectedH) < 0.01)
  }

  @Test("scaleToDevice recurses into children")
  func scaleRecursesChildren() {
    let child = AXNodeBuilder.button("A", at: (100, 200))
    let parent = AXNodeBuilder.node(role: "AXGroup", children: [child])

    let result = AXTreeReader.scaleToDevice(parent, scaleX: 2.0, scaleY: 2.0)

    #expect(result.children.count == 1)
    // Child frame.x was 100 - 50 = 50. Scaled by 2.0 → 100
    #expect(abs(result.children[0].frame.x - 100.0) < 0.01)
  }

  @Test("scaleToDevice with identity scale (1.0) preserves coordinates")
  func identityScale() {
    let node = AXNodeBuilder.button("OK", at: (196, 426))
    let result = AXTreeReader.scaleToDevice(node, scaleX: 1.0, scaleY: 1.0)

    #expect(result.frame.x == node.frame.x)
    #expect(result.frame.y == node.frame.y)
    #expect(result.frame.width == node.frame.width)
    #expect(result.frame.height == node.frame.height)
  }

  // MARK: - findScreenContent

  @Test("findScreenContent finds AXGroup with width>300 height>700 at depth>=2")
  func findsScreenContent() {
    let tree = AXNodeBuilder.simulatorTree(
      windowOrigin: (100, 200),
      windowSize: (359, 778)
    )

    let result = AXTreeReader.findScreenContent(tree)

    #expect(result != nil)
    #expect(result?.node.role == "AXGroup")
    #expect(result?.origin.x == 100)
    #expect(result?.origin.y == 200)
    #expect(result?.origin.width == 359)
    #expect(result?.origin.height == 778)
  }

  @Test("findScreenContent with deviceName scopes to matching window")
  func scopesToDeviceName() {
    // Two windows: one for iPhone 16, one for iPad
    let iPhoneScreen = AXNodeBuilder.screenContent(
      origin: (100, 200), size: (359, 778), depth: 2
    )
    let iPhoneWindow = AXNodeBuilder.node(
      role: "AXWindow", label: "iPhone 16",
      x: 100, y: 200, width: 359, height: 778,
      depth: 1, children: [iPhoneScreen]
    )

    let iPadScreen = AXNodeBuilder.screenContent(
      origin: (600, 200), size: (820, 1180), depth: 2
    )
    let iPadWindow = AXNodeBuilder.node(
      role: "AXWindow", label: "iPad Air",
      x: 600, y: 200, width: 820, height: 1180,
      depth: 1, children: [iPadScreen]
    )

    let root = AXNodeBuilder.node(
      role: "AXApplication", label: "Simulator",
      depth: 0, children: [iPhoneWindow, iPadWindow]
    )

    let result = AXTreeReader.findScreenContent(root, deviceName: "iPhone 16")

    #expect(result != nil)
    #expect(result?.origin.x == 100) // iPhone window, not iPad
  }

  @Test("findScreenContent returns nil when no qualifying group exists")
  func returnsNilWhenNoContent() {
    let small = AXNodeBuilder.node(
      role: "AXGroup", x: 0, y: 0, width: 100, height: 100, depth: 2
    )
    let window = AXNodeBuilder.node(
      role: "AXWindow", depth: 1, children: [small]
    )
    let root = AXNodeBuilder.node(
      role: "AXApplication", depth: 0, children: [window]
    )

    let result = AXTreeReader.findScreenContent(root)

    #expect(result == nil)
  }

  @Test("findScreenContent ignores AXGroup at depth < 2")
  func ignoresShallowGroup() {
    // An AXGroup directly under root (depth 1) — shouldn't match
    let group = AXNodeBuilder.node(
      role: "AXGroup", x: 0, y: 0, width: 400, height: 800, depth: 1
    )
    let root = AXNodeBuilder.node(
      role: "AXApplication", depth: 0, children: [group]
    )

    let result = AXTreeReader.findScreenContent(root)

    #expect(result == nil)
  }

  // MARK: - collectInteractive

  @Test("collectInteractive returns only interactive elements from tree")
  func collectsInteractive() {
    let button = AXNodeBuilder.button("Sign In", at: (196, 400))
    let text = AXNodeBuilder.text("Welcome", at: (0, 100))
    let link = AXNodeBuilder.link("Privacy", at: (196, 800))
    let group = AXNodeBuilder.node(role: "AXGroup", children: [button, text, link])

    let interactive = AXTreeReader.collectInteractive(group)

    #expect(interactive.count == 2) // button + link, not text or group
    for el in interactive {
      #expect(el.isInteractive)
    }
  }

  @Test("collectInteractive on a tree with no interactive elements returns empty")
  func collectsEmptyForNoInteractive() {
    let text1 = AXNodeBuilder.text("Hello", at: (0, 0))
    let text2 = AXNodeBuilder.text("World", at: (0, 30))
    let group = AXNodeBuilder.node(role: "AXGroup", children: [text1, text2])

    let interactive = AXTreeReader.collectInteractive(group)

    #expect(interactive.isEmpty)
  }

  // MARK: - countByRole / totalCount

  @Test("countByRole tallies all roles in tree")
  func countByRole() {
    let button1 = AXNodeBuilder.button("A", at: (100, 100))
    let button2 = AXNodeBuilder.button("B", at: (200, 200))
    let text = AXNodeBuilder.text("Label", at: (0, 0))
    let group = AXNodeBuilder.node(role: "AXGroup", children: [button1, button2, text])

    let counts = AXTreeReader.countByRole(group)

    #expect(counts["AXButton"] == 2)
    #expect(counts["AXStaticText"] == 1)
    #expect(counts["AXGroup"] == 1)
  }

  @Test("totalCount returns total node count including root")
  func totalCount() {
    let child1 = AXNodeBuilder.button("A", at: (100, 100))
    let child2 = AXNodeBuilder.text("B", at: (200, 200))
    let root = AXNodeBuilder.node(role: "AXGroup", children: [child1, child2])

    #expect(AXTreeReader.totalCount(root) == 3) // root + 2 children
  }
}
