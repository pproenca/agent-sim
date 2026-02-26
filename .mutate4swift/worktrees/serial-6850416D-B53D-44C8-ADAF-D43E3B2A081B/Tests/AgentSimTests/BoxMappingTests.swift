import Testing
import Foundation
@testable import AgentSimLib

@Suite("BoxMapping — persistence round-trips")
struct BoxMappingTests {

  @Test("Save then load round-trips all entries")
  func roundTrip() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("agentsim-box-\(UUID().uuidString)")
    let path = dir.appendingPathComponent("boxes.json").path

    let elements: [ScreenAnnotator.AnnotatedElement] = [
      .init(box: 1, frame: CGRect(x: 10, y: 20, width: 100, height: 44), label: "Home"),
      .init(box: 2, frame: CGRect(x: 50, y: 200, width: 200, height: 60), label: "Sign In"),
      .init(box: 3, frame: CGRect(x: 0, y: 800, width: 80, height: 40), label: "Profile"),
    ]

    try ScreenAnnotator.saveBoxMapping(elements, to: path)
    let loaded = try ScreenAnnotator.loadBoxMapping(from: path)

    #expect(loaded.count == 3)

    #expect(loaded[0].box == 1)
    #expect(loaded[0].label == "Home")
    #expect(loaded[0].tapX == 60) // midX of (10, width: 100)
    #expect(loaded[0].tapY == 42) // midY of (20, height: 44)

    #expect(loaded[1].box == 2)
    #expect(loaded[1].label == "Sign In")
    #expect(loaded[1].tapX == 150) // midX of (50, width: 200)

    #expect(loaded[2].box == 3)
    #expect(loaded[2].label == "Profile")
  }

  @Test("Loading from nonexistent file throws")
  func loadNonexistent() {
    #expect(throws: (any Error).self) {
      try ScreenAnnotator.loadBoxMapping(from: "/nonexistent/boxes.json")
    }
  }

  @Test("Empty elements array saves valid JSON")
  func emptyArray() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("agentsim-box-\(UUID().uuidString)")
    let path = dir.appendingPathComponent("boxes.json").path

    try ScreenAnnotator.saveBoxMapping([], to: path)
    let loaded = try ScreenAnnotator.loadBoxMapping(from: path)

    #expect(loaded.isEmpty)
  }

  @Test("buildElements assigns sequential box numbers across all categories")
  func buildElementsSequential() {
    let analysis = ScreenAnalysis(
      fingerprint: "abc12345",
      screenName: "Test",
      elementCount: 10,
      interactiveCount: 5,
      warning: nil,
      tabs: [
        .init(label: "Home", tapX: 60, tapY: 830, isSelected: true),
        .init(label: "Schedule", tapX: 150, tapY: 830, isSelected: false),
      ],
      navigation: [
        .init(role: "AXButton", name: "Back", identifier: "", tapX: 30, tapY: 50, width: 44, height: 44),
      ],
      actions: [
        .init(role: "AXButton", name: "Submit", identifier: "", tapX: 196, tapY: 400, width: 120, height: 44),
      ],
      content: [],
      destructive: [
        .init(role: "AXButton", name: "Delete", identifier: "", tapX: 196, tapY: 700, width: 100, height: 44),
      ],
      disabled: [],
      suggestedActions: []
    )

    let elements = ScreenAnnotator.buildElements(from: analysis)

    // Order: tabs → navigation → actions → destructive → disabled
    #expect(elements.count == 5)
    #expect(elements[0].box == 1) // Tab: Home
    #expect(elements[0].label == "Home")
    #expect(elements[1].box == 2) // Tab: Schedule
    #expect(elements[2].box == 3) // Nav: Back
    #expect(elements[2].label == "Back")
    #expect(elements[3].box == 4) // Action: Submit
    #expect(elements[4].box == 5) // Destructive: Delete
    #expect(elements[4].label == "Delete")
  }
}
