import Testing
@testable import AgentSimLib

@Suite("AXNode — model properties")
struct AXNodeTests {

  // MARK: - Frame geometry

  @Test("centerX is midpoint of x and width")
  func centerX() {
    let frame = AXNode.Frame(x: 100, y: 50, width: 200, height: 44)
    #expect(frame.centerX == 200) // 100 + 200/2
  }

  @Test("centerY is midpoint of y and height")
  func centerY() {
    let frame = AXNode.Frame(x: 100, y: 50, width: 200, height: 44)
    #expect(frame.centerY == 72) // 50 + 44/2
  }

  @Test("offsetBy subtracts dx/dy from position, preserves size")
  func offsetBy() {
    let frame = AXNode.Frame(x: 300, y: 400, width: 100, height: 44)
    let offset = frame.offsetBy(dx: 100, dy: 200)

    #expect(offset.x == 200)
    #expect(offset.y == 200)
    #expect(offset.width == 100)
    #expect(offset.height == 44)
  }

  @Test("offsetBy with negative deltas shifts position forward")
  func offsetByNegative() {
    let frame = AXNode.Frame(x: 50, y: 50, width: 100, height: 44)
    let offset = frame.offsetBy(dx: -100, dy: -200)

    #expect(offset.x == 150)
    #expect(offset.y == 250)
  }

  @Test("Frame.zero has all fields at zero")
  func frameZero() {
    let frame = AXNode.Frame.zero
    #expect(frame.x == 0)
    #expect(frame.y == 0)
    #expect(frame.width == 0)
    #expect(frame.height == 0)
  }

  // MARK: - isInteractive

  @Test(
    "Interactive roles are recognized",
    arguments: [
      "AXButton", "AXLink", "AXTextField", "AXSecureTextField",
      "AXCell", "AXCheckBox", "AXRadioButton", "AXSlider",
      "AXSwitch", "AXToggle", "AXPopUpButton", "AXComboBox",
      "AXSegmentedControl", "AXTabGroup",
    ]
  )
  func interactiveRoles(role: String) {
    let node = AXNodeBuilder.node(role: role)
    #expect(node.isInteractive)
  }

  @Test(
    "Non-interactive roles are excluded",
    arguments: ["AXStaticText", "AXImage", "AXGroup", "AXScrollArea", "AXWindow", "AXApplication"]
  )
  func nonInteractiveRoles(role: String) {
    let node = AXNodeBuilder.node(role: role)
    #expect(!node.isInteractive)
  }

  // MARK: - displayName fallback

  @Test("displayName prefers label first")
  func displayNameLabel() {
    let node = AXNodeBuilder.node(
      role: "AXButton",
      label: "Sign In",
      identifier: "sign_in_button",
      value: "some value"
    )
    #expect(node.displayName == "Sign In")
  }

  @Test("displayName falls back to accessibilityDescription when label is empty")
  func displayNameDescription() {
    let node = AXNode(
      role: "AXButton",
      label: "",
      identifier: "btn",
      value: "val",
      roleDescription: "",
      accessibilityDescription: "Accessibility Desc",
      help: "",
      enabled: true,
      frame: .zero,
      depth: 0,
      children: []
    )
    #expect(node.displayName == "Accessibility Desc")
  }

  @Test("displayName falls back to value when label and description are empty")
  func displayNameValue() {
    let node = AXNodeBuilder.node(
      role: "AXButton",
      label: "",
      value: "Toggle On"
    )
    #expect(node.displayName == "Toggle On")
  }

  @Test("displayName falls back to identifier when all text fields are empty")
  func displayNameIdentifier() {
    let node = AXNodeBuilder.node(
      role: "AXButton",
      label: "",
      identifier: "my_button"
    )
    #expect(node.displayName == "my_button")
  }

  @Test("displayName falls back to role as last resort")
  func displayNameRole() {
    let node = AXNodeBuilder.node(role: "AXButton")
    #expect(node.displayName == "AXButton")
  }

  // MARK: - flattened()

  @Test("flattened returns self when node has no children")
  func flattenedLeaf() {
    let node = AXNodeBuilder.button("OK", at: (100, 200))
    #expect(node.flattened().count == 1)
  }

  @Test("flattened returns all descendants in order")
  func flattenedTree() {
    let tree = AXNodeBuilder.node(
      role: "AXGroup",
      children: [
        AXNodeBuilder.button("A", at: (50, 50)),
        AXNodeBuilder.node(
          role: "AXGroup",
          children: [
            AXNodeBuilder.button("B", at: (100, 100)),
            AXNodeBuilder.text("C", at: (150, 150)),
          ]
        ),
      ]
    )
    let flat = tree.flattened()
    #expect(flat.count == 5) // root + A + group + B + C
    #expect(flat[0].role == "AXGroup")
    #expect(flat[1].displayName == "A")
    #expect(flat[2].role == "AXGroup")
    #expect(flat[3].displayName == "B")
    #expect(flat[4].displayName == "C")
  }
}
