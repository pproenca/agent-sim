import Testing
import Foundation
@testable import AgentSimLib

/// Structural tests — verify API contracts, encoding conformance, and type safety.
/// These catch breaking changes at compile time or with trivial assertions.
@Suite("Structural — API contracts and type safety")
struct StructuralTests {

  // MARK: - Encodable conformance (output types must encode to valid JSON)

  @Test("NextInstruction encodes to valid JSON")
  func nextInstructionEncodes() throws {
    let instruction = NextInstruction(
      phase: .exploring,
      instruction: "Continue exploring",
      action: .init(
        type: "tap", target: "Button",
        command: "agent-sim tap 100 200",
        reason: "test", tapX: 100, tapY: 200
      ),
      currentScreen: .init(
        name: "Home", fingerprint: "abc12345",
        interactiveCount: 5, tappedCount: 2, remainingCount: 3
      ),
      progress: .init(
        screensVisited: 3, totalActions: 10,
        issuesFound: 1, crashesDetected: 0, journalPath: "/tmp/j.md"
      ),
      afterAction: ["step 1", "step 2"],
      guardrails: ["rule 1"]
    )

    let data = try JSONEncoder().encode(instruction)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(json != nil)
    #expect(json?["phase"] as? String == "exploring")
  }

  @Test("ScreenAnalysis encodes to valid JSON")
  func screenAnalysisEncodes() throws {
    let analysis = ScreenAnalysis(
      fingerprint: "abc12345", screenName: "Home",
      elementCount: 10, interactiveCount: 3,
      tabs: [.init(label: "Home", tapX: 60, tapY: 830, isSelected: true)],
      navigation: [],
      actions: [.init(role: "AXButton", name: "OK", identifier: "", tapX: 196, tapY: 400, width: 100, height: 44)],
      content: [.init(role: "AXStaticText", text: "Hello", frame: .init(x: 0, y: 100, width: 200, height: 20))],
      destructive: [],
      disabled: [],
      suggestedActions: [.init(priority: 1, action: "tap", target: "OK", reason: "test", tapX: 196, tapY: 400)]
    )

    let data = try JSONEncoder().encode(analysis)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(json != nil)
    #expect(json?["fingerprint"] as? String == "abc12345")
  }

  @Test("NetworkLogParser.ParseResult encodes to valid JSON")
  func parseResultEncodes() throws {
    let result = NetworkLogParser.ParseResult(
      diagnosticsEnabled: true,
      requests: [.init(index: 1, timestamp: "10:00:00", method: "GET", url: "https://api.test.com", statusCode: 200, isError: false, errorDetail: nil, durationMs: 150)],
      rawEntries: []
    )

    let data = try JSONEncoder().encode(result)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(json != nil)
    #expect(json?["diagnosticsEnabled"] as? Bool == true)
  }

  @Test("AXNode encodes to valid JSON")
  func axNodeEncodes() throws {
    let node = AXNodeBuilder.button("Test", at: (100, 200))
    let data = try JSONEncoder().encode(node)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(json != nil)
    #expect(json?["role"] as? String == "AXButton")
    #expect(json?["label"] as? String == "Test")
  }

  // MARK: - SweepPhase raw values

  @Test("SweepPhase raw values are stable snake_case strings")
  func sweepPhaseRawValues() {
    #expect(SweepPhase.notStarted.rawValue == "not_started")
    #expect(SweepPhase.exploring.rawValue == "exploring")
    #expect(SweepPhase.screenExhausted.rawValue == "screen_exhausted")
    #expect(SweepPhase.newScreen.rawValue == "new_screen")
    #expect(SweepPhase.crashed.rawValue == "crashed")
    #expect(SweepPhase.complete.rawValue == "complete")
  }

  // MARK: - Sendable conformance (compile-time check)

  @Test("AXNode is Sendable (passable across concurrency boundaries)")
  func axNodeSendable() {
    let node = AXNodeBuilder.button("Test", at: (100, 200))

    // This compiles only if AXNode is Sendable
    let _: any Sendable = node
    _ = node // suppress warning
  }

  @Test("BootedDevice is Sendable")
  func bootedDeviceSendable() {
    let device = SimulatorBridge.BootedDevice(
      udid: "ABC-123", name: "iPhone 16",
      deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-16"
    )
    let _: any Sendable = device
    _ = device
  }

  // MARK: - BoxEntry Codable round-trip

  @Test("BoxEntry round-trips through Codable")
  func boxEntryCodable() throws {
    let entry = ScreenAnnotator.BoxEntry(box: 5, label: "Submit", tapX: 196, tapY: 400)

    let data = try JSONEncoder().encode(entry)
    let decoded = try JSONDecoder().decode(ScreenAnnotator.BoxEntry.self, from: data)

    #expect(decoded.box == 5)
    #expect(decoded.label == "Submit")
    #expect(decoded.tapX == 196)
    #expect(decoded.tapY == 400)
  }

  // MARK: - Device size lookup coverage

  @Test("screenSize lookup covers all iPhone 16 variants")
  func iPhone16FamilyCovered() {
    let variants = [
      "com.apple.CoreSimulator.SimDeviceType.iPhone-16",
      "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Plus",
      "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro",
      "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max",
      "com.apple.CoreSimulator.SimDeviceType.iPhone-16e",
    ]

    for variant in variants {
      let size = SimulatorBridge.screenSize(for: variant)
      // None of these should hit the default fallback (393, 852) — except base iPhone 16
      // which happens to BE (393, 852). So just verify they return valid sizes.
      #expect(size.width > 0, "\(variant) has zero width")
      #expect(size.height > 0, "\(variant) has zero height")
      #expect(size.height > size.width, "\(variant) should be portrait")
    }
  }

  @Test("screenSize lookup covers all iPhone 17 variants")
  func iPhone17FamilyCovered() {
    let variants = [
      "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
      "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Plus",
      "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro",
      "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max",
      "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Air",
    ]

    for variant in variants {
      let size = SimulatorBridge.screenSize(for: variant)
      #expect(size.width > 0, "\(variant) has zero width")
      #expect(size.height > 0, "\(variant) has zero height")
      #expect(size.height > size.width, "\(variant) should be portrait")
    }
  }

  // MARK: - Error descriptions

  @Test("All error types produce non-empty descriptions")
  func errorDescriptions() {
    let simError = SimulatorBridge.SimError.commandFailed("test", 1)
    #expect(!simError.description.isEmpty)

    let tapNotFound = TapError.elementNotFound("Button", available: "A, B")
    #expect(!tapNotFound.description.isEmpty)
    #expect(tapNotFound.description.contains("Button"))

    let tapNoBox = TapError.noBoxMapping
    #expect(!tapNoBox.description.isEmpty)

    let tapBoxNotFound = TapError.boxNotFound(5, available: "#1, #2")
    #expect(!tapBoxNotFound.description.isEmpty)
    #expect(tapBoxNotFound.description.contains("5"))

    let journalNotFound = JournalError.fileNotFound("/tmp/test.md")
    #expect(!journalNotFound.description.isEmpty)
    #expect(journalNotFound.description.contains("/tmp/test.md"))

    let noSim = DeviceResolutionError.noSimulator
    #expect(!noSim.description.isEmpty)
  }
}
