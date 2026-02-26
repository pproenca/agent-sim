import Testing
@testable import AgentSimLib

@Suite("Coordinate transforms — AXTreeReader utilities")
struct CoordinateTransformTests {

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
