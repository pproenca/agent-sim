import ArgumentParser
import Foundation

struct Explore: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Observe the current screen like a QA tester. Classifies all elements, computes fingerprint, and suggests next actions."
  )

  @Flag(name: .long, help: "Human-readable output instead of JSON.")
  var pretty = false

  @Option(name: .long, help: "Maximum tree depth.")
  var maxDepth: Int = 20

  @Option(name: .long, help: "Save a plain screenshot to this path (no annotations).")
  var screenshot: String?

  @Flag(name: .long, help: "Capture annotated screenshot with numbered bounding boxes. Saves to a default path. Enables tap --box N.")
  var annotate = false

  func run() async throws {
    let device = try await SimulatorBridge.resolveDevice()
    let simNode = try await AXTreeReader.readDeviceTree(simulatorUDID: device.udid, maxDepth: maxDepth)
    let analysis = ScreenAnalyzer.analyze(simNode)

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

    if pretty {
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
