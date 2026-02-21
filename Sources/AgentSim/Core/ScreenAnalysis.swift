import Foundation

/// Rich analysis of a simulator screen — the core output of the `explore` command.
/// Designed for AI agent consumption: pre-classified elements, suggested actions, fingerprint.
struct ScreenAnalysis: Encodable {
  let fingerprint: String
  let screenName: String
  let elementCount: Int
  let interactiveCount: Int
  let tabs: [TabItem]
  let navigation: [ClassifiedElement]
  let actions: [ClassifiedElement]
  let content: [ContentElement]
  let destructive: [ClassifiedElement]
  let disabled: [ClassifiedElement]
  let suggestedActions: [SuggestedAction]

  struct TabItem: Encodable {
    let label: String
    let tapX: Int
    let tapY: Int
    let isSelected: Bool
  }

  struct ClassifiedElement: Encodable {
    let role: String
    let name: String
    let identifier: String
    let tapX: Int
    let tapY: Int
    let width: Int
    let height: Int
  }

  struct ContentElement: Encodable {
    let role: String
    let text: String
    let frame: FrameInfo
  }

  struct FrameInfo: Encodable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
  }

  struct SuggestedAction: Encodable {
    let priority: Int
    let action: String
    let target: String
    let reason: String
    let tapX: Int
    let tapY: Int
  }
}

// MARK: - Builder

enum ScreenAnalyzer {

  private static let destructiveLabels: Set<String> = [
    "delete", "remove", "sign out", "log out", "logout",
    "cancel membership", "deactivate", "reset"
  ]

  private static let navigationLabels: Set<String> = [
    "back", "close", "done", "cancel", "dismiss"
  ]

  static func analyze(_ tree: AXNode) -> ScreenAnalysis {
    let fingerprint = Fingerprinter.fingerprint(tree)
    let screenName = inferScreenName(tree)
    let allElements = flatten(tree)
    let interactive = allElements.filter(\.isInteractive)

    let tabs = extractTabs(tree)
    var navigation: [ScreenAnalysis.ClassifiedElement] = []
    var actions: [ScreenAnalysis.ClassifiedElement] = []
    var destructive: [ScreenAnalysis.ClassifiedElement] = []
    var disabled: [ScreenAnalysis.ClassifiedElement] = []

    for el in interactive {
      let classified = ScreenAnalysis.ClassifiedElement(
        role: el.role,
        name: el.displayName,
        identifier: el.identifier,
        tapX: Int(el.frame.centerX),
        tapY: Int(el.frame.centerY),
        width: Int(el.frame.width),
        height: Int(el.frame.height)
      )

      if !el.enabled {
        disabled.append(classified)
      } else if isDestructive(el) {
        destructive.append(classified)
      } else if isNavigation(el) {
        navigation.append(classified)
      } else {
        actions.append(classified)
      }
    }

    let content = extractContent(allElements)
    let suggestions = buildSuggestions(
      actions: actions, navigation: navigation, tabs: tabs, tree: tree
    )

    return ScreenAnalysis(
      fingerprint: fingerprint,
      screenName: screenName,
      elementCount: allElements.count,
      interactiveCount: interactive.count,
      tabs: tabs,
      navigation: navigation,
      actions: actions,
      content: content,
      destructive: destructive,
      disabled: disabled,
      suggestedActions: suggestions
    )
  }

  // MARK: - Classification

  private static func isDestructive(_ el: AXNode) -> Bool {
    let name = el.displayName.lowercased()
    return destructiveLabels.contains(where: { name.contains($0) })
  }

  private static func isNavigation(_ el: AXNode) -> Bool {
    let name = el.displayName.lowercased()
    // Top-of-screen buttons (y < 100) with navigation labels
    if el.frame.centerY < 100 && navigationLabels.contains(where: { name.contains($0) }) {
      return true
    }
    return false
  }

  private static func extractTabs(_ tree: AXNode) -> [ScreenAnalysis.TabItem] {
    // Find AXTabGroup and extract its children
    func findTabGroup(_ node: AXNode) -> AXNode? {
      if node.role == "AXTabGroup" { return node }
      for child in node.children {
        if let found = findTabGroup(child) { return found }
      }
      return nil
    }

    guard let tabGroup = findTabGroup(tree) else { return [] }

    return tabGroup.children.compactMap { child in
      let name = child.displayName
      guard !name.isEmpty else { return nil }
      return ScreenAnalysis.TabItem(
        label: name,
        tapX: Int(child.frame.centerX),
        tapY: Int(child.frame.centerY),
        isSelected: child.value == "1" || child.value.lowercased() == "true"
      )
    }
  }

  private static func extractContent(_ elements: [AXNode]) -> [ScreenAnalysis.ContentElement] {
    elements
      .filter { $0.role == "AXStaticText" && !$0.displayName.isEmpty }
      .prefix(20) // Cap to avoid huge output
      .map { el in
        ScreenAnalysis.ContentElement(
          role: el.role,
          text: el.displayName,
          frame: ScreenAnalysis.FrameInfo(
            x: Int(el.frame.x), y: Int(el.frame.y),
            width: Int(el.frame.width), height: Int(el.frame.height)
          )
        )
      }
  }

  private static func buildSuggestions(
    actions: [ScreenAnalysis.ClassifiedElement],
    navigation: [ScreenAnalysis.ClassifiedElement],
    tabs: [ScreenAnalysis.TabItem],
    tree: AXNode
  ) -> [ScreenAnalysis.SuggestedAction] {
    var suggestions: [ScreenAnalysis.SuggestedAction] = []
    var priority = 1

    // Suggest scrolling if there might be off-screen content
    if tree.frame.height > 900 {
      suggestions.append(.init(
        priority: priority, action: "scroll-down", target: "screen",
        reason: "Screen may have off-screen content below the fold",
        tapX: 0, tapY: 0
      ))
      priority += 1
    }

    // Suggest tapping each action element (capped at 10)
    for action in actions.prefix(10) {
      suggestions.append(.init(
        priority: priority,
        action: "tap",
        target: action.name,
        reason: "Interactive \(action.role) element",
        tapX: action.tapX,
        tapY: action.tapY
      ))
      priority += 1
    }

    // Suggest switching to unselected tabs
    for tab in tabs where !tab.isSelected {
      suggestions.append(.init(
        priority: priority,
        action: "tap-tab",
        target: tab.label,
        reason: "Switch to unvisited tab",
        tapX: tab.tapX,
        tapY: tab.tapY
      ))
      priority += 1
    }

    return suggestions
  }

  // MARK: - Screen Name Inference

  private static func inferScreenName(_ tree: AXNode) -> String {
    // Look for navigation title (AXStaticText with large font near top)
    let flat = flatten(tree)

    // Strategy 1: Find a prominent text element near the top of the screen
    let topTexts = flat
      .filter { $0.role == "AXStaticText" && $0.frame.centerY < 120 && !$0.displayName.isEmpty }
      .sorted(by: { $0.frame.width > $1.frame.width })

    if let title = topTexts.first {
      return title.displayName
    }

    // Strategy 2: Look for the first large text element
    let largeTexts = flat
      .filter { $0.role == "AXStaticText" && $0.frame.height > 24 && !$0.displayName.isEmpty }
      .sorted(by: { $0.frame.y < $1.frame.y })

    if let title = largeTexts.first {
      return title.displayName
    }

    return "Unknown Screen"
  }

  // MARK: - Helpers

  private static func flatten(_ node: AXNode) -> [AXNode] {
    var result = [node]
    for child in node.children {
      result.append(contentsOf: flatten(child))
    }
    return result
  }
}
