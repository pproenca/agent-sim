import ArgumentParser
import Foundation

struct Explore: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Observe the current screen like a QA tester. Classifies all elements, computes fingerprint, and suggests next actions."
  )

  @Flag(name: .short, help: "Interactive-only output: shows @eN refs for tappable elements. Minimal tokens.")
  var interactive = false

  @Flag(name: .long, help: "Human-readable output instead of JSON.")
  var pretty = false

  @Option(name: .long, help: "Maximum tree depth.")
  var maxDepth: Int = 20

  @Option(name: .long, help: "Save a plain screenshot to this path (no annotations).")
  var screenshot: String?

  @Flag(name: .long, help: "Capture annotated screenshot with numbered bounding boxes. Saves to a default path. Enables tap --box N.")
  var annotate = false

  @Flag(name: .long, help: "Raw accessibility tree output.")
  var raw = false

  @Flag(name: .long, help: "Output only the screen fingerprint hash.")
  var fingerprintOnly = false

  @Flag(name: .long, help: "Show what changed since last explore.")
  var diff = false

  func run() async throws {
    // --raw: raw accessibility tree (replaces old `describe`)
    if raw {
      try await runRaw()
      return
    }

    // --fingerprint: hash only (replaces old `fingerprint --hash-only`)
    if fingerprintOnly {
      try await runFingerprint()
      return
    }

    // --diff: show changes since last explore (replaces old `diff`)
    if diff {
      try await runDiff()
      return
    }

    // Default explore logic
    let device = try await SimulatorBridge.resolveDevice()
    let simNode = try await AXTreeReader.readDeviceTree(simulatorUDID: device.udid, maxDepth: maxDepth)
    let analysis = ScreenAnalyzer.analyze(simNode)

    // Load previous snapshot for diff hints (before overwriting)
    let previousSnapshot = try? RefStore.load()

    // Build and persist refs (always, so `tap @eN` works regardless of output mode)
    let refs = RefStore.buildRefs(from: analysis)
    let snapshot = RefSnapshot(
      fingerprint: analysis.fingerprint,
      screenName: analysis.screenName,
      interactiveCount: analysis.interactiveCount,
      elementCount: analysis.elementCount,
      timestamp: ISO8601DateFormatter().string(from: Date()),
      refs: refs
    )
    try RefStore.save(snapshot)

    // Plain screenshot (explicit path, no annotations)
    var screenshotPath: String?
    if let requestedPath = screenshot {
      screenshotPath = try await SimulatorBridge.screenshot(simulatorID: device.udid, path: requestedPath)
    }

    // Annotated screenshot (default path, numbered boxes, enables tap --box)
    var annotatedPath: String?
    if annotate {
      let deviceSize = SimulatorBridge.screenSize(for: device)
      let elements = ScreenAnnotator.buildElements(from: analysis)

      let capturePath = ScreenAnnotator.defaultScreenshotPath
      let plainCapture = try await SimulatorBridge.screenshot(simulatorID: device.udid, path: capturePath)
      try ScreenAnnotator.annotate(
        imagePath: plainCapture,
        elements: elements,
        deviceSize: deviceSize,
        outputPath: plainCapture
      )
      try ScreenAnnotator.saveBoxMapping(elements, to: ScreenAnnotator.defaultMappingPath)
      annotatedPath = plainCapture
    }

    if interactive {
      // Visual fallback: when AX tree has 0 interactive elements, use annotated screenshot
      if refs.isEmpty && analysis.elementCount > 0 {
        let fallbackRefs = try await visualFallback(device: device, analysis: analysis)
        // Re-save ref store with visual refs so tap @eN works
        let fallbackSnapshot = RefSnapshot(
          fingerprint: analysis.fingerprint,
          screenName: analysis.screenName,
          interactiveCount: fallbackRefs.count,
          elementCount: analysis.elementCount,
          timestamp: ISO8601DateFormatter().string(from: Date()),
          refs: fallbackRefs
        )
        try RefStore.save(fallbackSnapshot)
        printInteractive(analysis, refs: fallbackRefs, screenshotPath: screenshotPath, previous: previousSnapshot, fallbackMode: true)
      } else {
        printInteractive(analysis, refs: refs, screenshotPath: screenshotPath, previous: previousSnapshot)
      }
    } else if pretty {
      printPretty(analysis, screenshotPath: screenshotPath, annotatedPath: annotatedPath)
    } else {
      let output = ExploreOutput(
        analysis: analysis,
        screenshotPath: screenshotPath,
        annotatedScreenshotPath: annotatedPath
      )
      JSONOutput.print(output)
    }
  }

  // MARK: - Raw mode (old describe)

  private func runRaw() async throws {
    let device = try await SimulatorBridge.resolveDevice()
    let simNode = try await AXTreeReader.readDeviceTree(simulatorUDID: device.udid, maxDepth: maxDepth)

    if interactive {
      let elements = AXTreeReader.collectInteractive(simNode)
      if pretty {
        printRawInteractivePretty(elements)
      } else {
        JSONOutput.print(elements.map(RawInteractiveElement.init))
      }
    } else {
      if pretty {
        printRawTreePretty(simNode)
        printRawStats(simNode)
      } else {
        JSONOutput.print(simNode)
      }
    }
  }

  // MARK: - Fingerprint mode (old fingerprint --hash-only)

  private func runFingerprint() async throws {
    let device = try await SimulatorBridge.resolveDevice()
    let simNode = try await AXTreeReader.readDeviceTree(simulatorUDID: device.udid)
    let hash = Fingerprinter.fingerprint(simNode)
    print(hash)
  }

  // MARK: - Diff mode (old diff)

  private func runDiff() async throws {
    // Load previous snapshot
    let previous: RefSnapshot
    do {
      previous = try RefStore.load()
    } catch {
      print("No previous explore to diff against. Run 'agent-sim explore -i' first.")
      return
    }

    // Read current screen
    let device = try await SimulatorBridge.resolveDevice()
    let simNode = try await AXTreeReader.readDeviceTree(simulatorUDID: device.udid)
    let analysis = ScreenAnalyzer.analyze(simNode)
    let currentRefs = RefStore.buildRefs(from: analysis)

    // Quick check: same screen?
    if previous.fingerprint == analysis.fingerprint {
      print("[same] \(analysis.screenName) — no changes detected")
      return
    }

    // Screen changed
    print("Screen: \(previous.screenName) -> \(analysis.screenName)")
    print("")

    // Build lookup by name+role for comparison
    let prevByKey = Dictionary(
      previous.refs.map { ("\($0.role)|\($0.name)", $0) },
      uniquingKeysWith: { first, _ in first }
    )
    let currByKey = Dictionary(
      currentRefs.map { ("\($0.role)|\($0.name)", $0) },
      uniquingKeysWith: { first, _ in first }
    )

    let prevKeys = Set(prevByKey.keys)
    let currKeys = Set(currByKey.keys)

    let added = currKeys.subtracting(prevKeys)
    let removed = prevKeys.subtracting(currKeys)
    let shared = prevKeys.intersection(currKeys)

    if !added.isEmpty {
      print("Added:")
      for key in added.sorted() {
        if let ref = currByKey[key] {
          print("  @\(ref.ref) [\(ref.shortRole)] \"\(ref.name)\"")
        }
      }
      print("")
    }

    if !removed.isEmpty {
      print("Removed:")
      for key in removed.sorted() {
        if let ref = prevByKey[key] {
          print("  [\(ref.shortRole)] \"\(ref.name)\"")
        }
      }
      print("")
    }

    // Check for moved elements
    var moved: [(RefEntry, RefEntry)] = []
    for key in shared {
      if let prev = prevByKey[key], let curr = currByKey[key] {
        if prev.tapX != curr.tapX || prev.tapY != curr.tapY {
          moved.append((prev, curr))
        }
      }
    }

    if !moved.isEmpty {
      print("Moved:")
      for (prev, curr) in moved {
        print("  @\(curr.ref) [\(curr.shortRole)] \"\(curr.name)\" (\(prev.tapX),\(prev.tapY) -> \(curr.tapX),\(curr.tapY))")
      }
      print("")
    }

    if added.isEmpty && removed.isEmpty && moved.isEmpty {
      print("Elements are the same but fingerprint changed (content or layout shift).")
    }
  }

  // MARK: - Visual Fallback

  /// When AX tree has 0 interactive elements (Expo, bad accessibility), fall back to
  /// annotating all visible content elements as visual refs.
  private func visualFallback(
    device: SimulatorBridge.BootedDevice,
    analysis: ScreenAnalysis
  ) async throws -> [RefEntry] {
    let deviceSize = SimulatorBridge.screenSize(for: device)

    // Use content elements as visual targets (they have text labels and positions)
    var refs: [RefEntry] = []
    var index = 1
    for content in analysis.content {
      refs.append(RefEntry(
        ref: "e\(index)",
        role: "visual",
        name: content.text,
        identifier: "",
        tapX: content.frame.x + content.frame.width / 2,
        tapY: content.frame.y + content.frame.height / 2,
        width: content.frame.width,
        height: content.frame.height,
        enabled: true,
        category: "visual"
      ))
      index += 1
    }

    // Capture and annotate screenshot with ref labels
    let capturePath = ScreenAnnotator.defaultScreenshotPath
    let plainCapture = try await SimulatorBridge.screenshot(simulatorID: device.udid, path: capturePath)
    let elements = refs.map { ref in
      ScreenAnnotator.AnnotatedElement(
        box: Int(ref.ref.dropFirst()) ?? 0, // "e1" → 1
        frame: CGRect(
          x: Double(ref.tapX) - Double(ref.width) / 2,
          y: Double(ref.tapY) - Double(ref.height) / 2,
          width: Double(ref.width),
          height: Double(ref.height)
        ),
        label: ref.name
      )
    }
    let refLabels = refs.map { "@\($0.ref)" }
    try ScreenAnnotator.annotate(
      imagePath: plainCapture,
      elements: elements,
      deviceSize: deviceSize,
      outputPath: plainCapture,
      labels: refLabels
    )

    return refs
  }

  // MARK: - Interactive Output (explore -i)

  private func printInteractive(
    _ analysis: ScreenAnalysis,
    refs: [RefEntry],
    screenshotPath: String?,
    previous: RefSnapshot?,
    fallbackMode: Bool = false
  ) {
    let shortFP = String(analysis.fingerprint.prefix(8))

    if let warning = analysis.warning {
      print("WARNING: \(warning)")
      print("")
    }

    // Diff hint: [changed] or [same] vs previous explore
    if let prev = previous {
      if prev.fingerprint != analysis.fingerprint {
        let delta = analysis.interactiveCount - prev.interactiveCount
        let deltaStr: String
        if delta > 0 {
          deltaStr = " | +\(delta) interactive"
        } else if delta < 0 {
          deltaStr = " | \(delta) interactive"
        } else {
          deltaStr = ""
        }
        print("[changed] Was: \(prev.screenName) -> Now: \(analysis.screenName)\(deltaStr)")
      } else {
        print("[same] \(analysis.screenName) | \(analysis.interactiveCount) interactive")
      }
    }

    // Header line
    print("Screen: \(analysis.screenName) | \(analysis.elementCount) elements, \(analysis.interactiveCount) interactive | fp:\(shortFP)")

    if let path = screenshotPath {
      print("Screenshot: \(path)")
    }

    if fallbackMode {
      print("")
      print("[fallback: 0 interactive elements — using visual detection]")
      print("Screenshot: \(ScreenAnnotator.defaultScreenshotPath)")
    }

    if refs.isEmpty {
      print("")
      print("No interactive elements found. Use 'agent-sim screenshot' + 'tap <x> <y>'.")
      return
    }

    print("")
    for ref in refs {
      print(ref.interactiveLine)
    }
  }

  // MARK: - Pretty Output

  private func printPretty(
    _ analysis: ScreenAnalysis,
    screenshotPath: String?,
    annotatedPath: String?
  ) {
    if let warning = analysis.warning {
      print("WARNING: \(warning)")
      print("")
    }
    print("Screen: \(analysis.screenName)")
    print("Fingerprint: \(analysis.fingerprint)")
    print("Elements: \(analysis.elementCount) total, \(analysis.interactiveCount) interactive")
    if let path = screenshotPath {
      print("Screenshot: \(path)")
    }
    if let path = annotatedPath {
      print("Annotated: \(path)")
    }
    print("")

    var box = 1

    if !analysis.tabs.isEmpty {
      print("Tabs:")
      for tab in analysis.tabs {
        let marker = tab.isSelected ? " [SELECTED]" : ""
        if annotate {
          print("  #\(box) \(tab.label) tap=(\(tab.tapX),\(tab.tapY))\(marker)  →  tap --box \(box)")
        } else {
          print("  - \(tab.label) tap=(\(tab.tapX),\(tab.tapY))\(marker)")
        }
        box += 1
      }
      print("")
    }

    if !analysis.navigation.isEmpty {
      print("Navigation:")
      for nav in analysis.navigation {
        if annotate {
          print("  #\(box) [\(nav.role)] \"\(nav.name)\" tap=(\(nav.tapX),\(nav.tapY))  →  tap --box \(box)")
        } else {
          print("  - [\(nav.role)] \"\(nav.name)\" tap=(\(nav.tapX),\(nav.tapY))")
        }
        box += 1
      }
      print("")
    }

    if !analysis.actions.isEmpty {
      print("Actions (\(analysis.actions.count)):")
      for (i, action) in analysis.actions.enumerated() {
        let idStr = action.identifier.isEmpty ? "" : " id=\"\(action.identifier)\""
        if annotate {
          print("  #\(box) [\(action.role)] \"\(action.name)\"\(idStr)  →  tap --box \(box)")
        } else {
          print("  \(i + 1). [\(action.role)] \"\(action.name)\"\(idStr) tap=(\(action.tapX),\(action.tapY))")
        }
        box += 1
      }
      print("")
    }

    if !analysis.destructive.isEmpty {
      print("Destructive (SKIPPED):")
      for el in analysis.destructive {
        if annotate {
          print("  #\(box) ! \"\(el.name)\"  →  tap --box \(box)")
        } else {
          print("  ! \"\(el.name)\" tap=(\(el.tapX),\(el.tapY))")
        }
        box += 1
      }
      print("")
    }

    if !analysis.disabled.isEmpty {
      print("Disabled:")
      for el in analysis.disabled {
        if annotate {
          print("  #\(box) x \"\(el.name)\"")
        } else {
          print("  x \"\(el.name)\"")
        }
        box += 1
      }
      print("")
    }

    if !annotate && !analysis.suggestedActions.isEmpty {
      print("Suggested next actions:")
      for suggestion in analysis.suggestedActions.prefix(8) {
        print("  \(suggestion.priority). \(suggestion.action) \"\(suggestion.target)\" — \(suggestion.reason)")
      }
    }
  }

  // MARK: - Raw tree helpers (from old describe)

  private func printRawTreePretty(_ node: AXNode, indent: Int = 0) {
    let pad = String(repeating: "  ", count: indent)
    var parts: [String] = [node.role]
    if !node.label.isEmpty { parts.append("label=\"\(node.label)\"") }
    if !node.identifier.isEmpty { parts.append("id=\"\(node.identifier)\"") }
    if !node.accessibilityDescription.isEmpty && node.accessibilityDescription.count < 80 {
      parts.append("desc=\"\(node.accessibilityDescription)\"")
    }
    if !node.value.isEmpty && node.value.count < 60 { parts.append("value=\"\(node.value)\"") }
    if !node.enabled { parts.append("DISABLED") }
    if node.frame.width > 0 {
      parts.append("(\(Int(node.frame.x)),\(Int(node.frame.y)) \(Int(node.frame.width))x\(Int(node.frame.height)))")
    }
    print("\(pad)\(parts.joined(separator: " "))")
    for child in node.children {
      printRawTreePretty(child, indent: indent + 1)
    }
  }

  private func printRawStats(_ node: AXNode) {
    let total = AXTreeReader.totalCount(node)
    let interactive = AXTreeReader.collectInteractive(node)
    let byRole = AXTreeReader.countByRole(node)

    print("\n--- Stats ---")
    print("Elements: \(total)  Interactive: \(interactive.count)")
    print("Roles: \(byRole.sorted(by: { $0.value > $1.value }).map { "\($0.key):\($0.value)" }.joined(separator: " "))")
  }

  private func printRawInteractivePretty(_ elements: [AXNode]) {
    for el in elements {
      let cx = Int(el.frame.centerX)
      let cy = Int(el.frame.centerY)
      print("[\(el.role)] \"\(el.displayName)\" tap=(\(cx),\(cy)) size=\(Int(el.frame.width))x\(Int(el.frame.height))")
    }
  }

}

// MARK: - JSON Output

private struct ExploreOutput: Encodable {
  let fingerprint: String
  let screenName: String
  let elementCount: Int
  let interactiveCount: Int
  let warning: String?
  let tabs: [ScreenAnalysis.TabItem]
  let navigation: [ScreenAnalysis.ClassifiedElement]
  let actions: [ScreenAnalysis.ClassifiedElement]
  let content: [ScreenAnalysis.ContentElement]
  let destructive: [ScreenAnalysis.ClassifiedElement]
  let disabled: [ScreenAnalysis.ClassifiedElement]
  let suggestedActions: [ScreenAnalysis.SuggestedAction]
  let screenshotPath: String?
  let annotatedScreenshotPath: String?

  init(
    analysis: ScreenAnalysis,
    screenshotPath: String?,
    annotatedScreenshotPath: String?
  ) {
    self.fingerprint = analysis.fingerprint
    self.screenName = analysis.screenName
    self.elementCount = analysis.elementCount
    self.interactiveCount = analysis.interactiveCount
    self.warning = analysis.warning
    self.tabs = analysis.tabs
    self.navigation = analysis.navigation
    self.actions = analysis.actions
    self.content = analysis.content
    self.destructive = analysis.destructive
    self.disabled = analysis.disabled
    self.suggestedActions = analysis.suggestedActions
    self.screenshotPath = screenshotPath
    self.annotatedScreenshotPath = annotatedScreenshotPath
  }
}

// MARK: - Raw interactive element model (for --raw JSON output)

private struct RawInteractiveElement: Encodable {
  let role: String
  let name: String
  let identifier: String
  let tapX: Int
  let tapY: Int
  let width: Int
  let height: Int
  let enabled: Bool

  init(_ node: AXNode) {
    role = node.role
    name = node.displayName
    identifier = node.identifier
    tapX = Int(node.frame.centerX)
    tapY = Int(node.frame.centerY)
    width = Int(node.frame.width)
    height = Int(node.frame.height)
    enabled = node.enabled
  }
}
