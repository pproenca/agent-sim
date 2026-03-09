import Testing
import Foundation
@testable import AgentSimLib

/// Structural tests — verify API contracts, encoding conformance, and type safety.
/// These catch breaking changes at compile time or with trivial assertions.
@Suite("Structural — API contracts and type safety")
struct StructuralTests {

  // MARK: - Encodable conformance (output types must encode to valid JSON)

  @Test("ScreenAnalysis encodes to valid JSON")
  func screenAnalysisEncodes() throws {
    let analysis = ScreenAnalysis(
      fingerprint: "abc12345", screenName: "Home",
      elementCount: 10, interactiveCount: 3,
      warning: nil,
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

  @Test("AXNode encodes to valid JSON")
  func axNodeEncodes() throws {
    let node = AXNodeBuilder.button("Test", at: (100, 200))
    let data = try JSONEncoder().encode(node)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(json != nil)
    #expect(json?["role"] as? String == "AXButton")
    #expect(json?["label"] as? String == "Test")
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
      screenWidthPoints: 393, screenHeightPoints: 852
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

  // MARK: - SimGroup subcommands

  @Test("sim command group has expected subcommands")
  func simGroupSubcommands() {
    let config = SimGroup.configuration
    #expect(config.commandName == "sim")
    let names = config.subcommands.map { $0.configuration.commandName ?? "" }
    #expect(names.contains("boot"))
    #expect(names.contains("list"))
    #expect(names.contains("shutdown"))
    #expect(names.contains("install"))
    #expect(names.contains("apps"))
  }

  // MARK: - UIGroup subcommands

  @Test("ui command group has assert, wait, and find subcommands")
  func uiGroupSubcommands() {
    let config = UIGroup.configuration
    #expect(config.commandName == "ui")
    let names = config.subcommands.map { $0.configuration.commandName ?? "" }
    #expect(names.contains("assert"))
    #expect(names.contains("wait"))
    #expect(names.contains("find"))
  }

  @Test("ui assert has visible, hidden, text, enabled subcommands")
  func uiAssertSubcommands() {
    let config = UIAssertGroup.configuration
    #expect(config.commandName == "assert")
    let names = config.subcommands.map { $0.configuration.commandName ?? "" }
    #expect(names.contains("visible"))
    #expect(names.contains("hidden"))
    #expect(names.contains("text"))
    #expect(names.contains("enabled"))
  }

  // MARK: - ConfigGroup subcommands

  @Test("config command group has set and show subcommands")
  func configGroupSubcommands() {
    let config = ConfigGroup.configuration
    #expect(config.commandName == "config")
    let names = config.subcommands.map { $0.configuration.commandName ?? "" }
    #expect(names.contains("set"))
    #expect(names.contains("show"))
  }

  // MARK: - ProjectGroupCmd subcommands

  @Test("project command group has context subcommand")
  func projectGroupSubcommands() {
    let config = ProjectGroupCmd.configuration
    #expect(config.commandName == "project")
    let names = config.subcommands.map { $0.configuration.commandName ?? "" }
    #expect(names.contains("context"))
  }

  // MARK: - Stop command

  @Test("stop command exists with expected command name")
  func stopCommandExists() {
    let config = Stop.configuration
    #expect(config.commandName == "stop")
  }

  // MARK: - Explore flags (merged describe, fingerprint, diff)

  @Test("Explore has --raw, --fingerprint, --diff flags and old commands are removed")
  func exploreMergedFlags() {
    let config = AgentSim.configuration
    let subcommandTypes = config.subcommands.map { String(describing: $0) }

    // Old standalone commands removed
    #expect(!subcommandTypes.contains("Describe"))
    #expect(!subcommandTypes.contains("FingerprintCmd"))
    #expect(!subcommandTypes.contains("Diff"))

    // Explore still registered
    #expect(subcommandTypes.contains("Explore"))

    // Explore struct has the merged flags
    let mirror = Mirror(reflecting: Explore())
    let labels = mirror.children.compactMap(\.label)
    #expect(labels.contains("_raw"))
    #expect(labels.contains("_fingerprintOnly"))
    #expect(labels.contains("_diff"))
  }

  // MARK: - Removed commands

  @Test("removed commands are not registered")
  func removedCommands() {
    let names = AgentSim.configuration.subcommands.map {
      String(describing: $0)
    }
    // These should NOT be in the subcommands
    for removed in ["Next", "Journal", "Network", "Init", "Use", "Status"] {
      #expect(!names.contains(where: { $0.contains(removed) }))
    }
  }

  // MARK: - Error descriptions

  @Test("All error types produce non-empty descriptions")
  func errorDescriptions() {
    let simError = SimulatorBridge.SimError.commandFailed("test", 1)
    #expect(!simError.localizedDescription.isEmpty)

    let tapNotFound = TapError.elementNotFound("Button", available: "A, B")
    #expect(!tapNotFound.localizedDescription.isEmpty)
    #expect(tapNotFound.localizedDescription.contains("Button"))

    let tapNoBox = TapError.noBoxMapping
    #expect(!tapNoBox.localizedDescription.isEmpty)

    let tapBoxNotFound = TapError.boxNotFound(5, available: "#1, #2")
    #expect(!tapBoxNotFound.localizedDescription.isEmpty)
    #expect(tapBoxNotFound.localizedDescription.contains("5"))

    let noSim = DeviceResolutionError.noSimulator
    #expect(!noSim.localizedDescription.isEmpty)
  }
}
