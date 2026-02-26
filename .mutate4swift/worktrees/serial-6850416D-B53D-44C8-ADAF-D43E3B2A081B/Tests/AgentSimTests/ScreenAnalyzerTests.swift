import Testing
@testable import AgentSimLib

@Suite("ScreenAnalyzer — element classification")
struct ScreenAnalyzerTests {

  // MARK: - Destructive classification

  @Test("Button with 'delete' label is classified as destructive")
  func deleteIsDestructive() {
    let tree = screenWithButton("Delete Item", at: (196, 400))
    let analysis = ScreenAnalyzer.analyze(tree)

    #expect(analysis.destructive.count == 1)
    #expect(analysis.destructive[0].name == "Delete Item")
    #expect(analysis.actions.isEmpty)
  }

  @Test("Button with 'Sign Out' label is classified as destructive (case-insensitive)")
  func signOutIsDestructive() {
    let tree = screenWithButton("Sign Out", at: (196, 400))
    let analysis = ScreenAnalyzer.analyze(tree)

    #expect(analysis.destructive.count == 1)
    #expect(analysis.actions.isEmpty)
  }

  @Test("Button with 'remove' in label is classified as destructive")
  func removeIsDestructive() {
    let tree = screenWithButton("Remove from list", at: (196, 400))
    let analysis = ScreenAnalyzer.analyze(tree)

    #expect(analysis.destructive.count == 1)
  }

  // MARK: - Navigation classification

  @Test("'Back' button near top of screen (y < 100) is classified as navigation")
  func backIsNavigation() {
    // Center at y=50, so the element is well within the top 100pt
    let tree = screenWithButton("Back", at: (30, 50))
    let analysis = ScreenAnalyzer.analyze(tree)

    #expect(analysis.navigation.count == 1)
    #expect(analysis.navigation[0].name == "Back")
    #expect(analysis.actions.isEmpty)
  }

  @Test("'Close' button near top is classified as navigation")
  func closeIsNavigation() {
    let tree = screenWithButton("Close", at: (360, 50))
    let analysis = ScreenAnalyzer.analyze(tree)

    #expect(analysis.navigation.count == 1)
  }

  @Test("Button inside nav bar is classified as navigation regardless of label")
  func buttonInsideNavBarIsNavigation() {
    let editButton = AXNodeBuilder.button("Edit", at: (350, 22))
    let navBarWithButton = AXNodeBuilder.node(
      role: "AXNavigationBar",
      x: 0, y: 0, width: 393, height: 44, depth: 2,
      children: [editButton]
    )
    let tree = AXNodeBuilder.screenContent(children: [navBarWithButton])
    let analysis = ScreenAnalyzer.analyze(tree)

    #expect(analysis.navigation.count == 1)
    #expect(analysis.navigation[0].name == "Edit")
  }

  @Test("'Back' button at y=101 outside nav bar is classified as action")
  func backOutsideNavBarIsAction() {
    let tree = screenWithButton("Back", at: (30, 101))
    let analysis = ScreenAnalyzer.analyze(tree)

    #expect(analysis.navigation.isEmpty)
    #expect(analysis.actions.count == 1)
  }

  @Test("'Delete' button inside nav bar is still destructive")
  func deleteInsideNavBarStillDestructive() {
    let deleteButton = AXNodeBuilder.button("Delete", at: (350, 22))
    let navBar = AXNodeBuilder.node(
      role: "AXNavigationBar",
      x: 0, y: 0, width: 393, height: 44, depth: 2,
      children: [deleteButton]
    )
    let tree = AXNodeBuilder.screenContent(children: [navBar])
    let analysis = ScreenAnalyzer.analyze(tree)

    #expect(analysis.destructive.count == 1)
    #expect(analysis.navigation.isEmpty)
  }

  @Test("Button inside nav bar with no keyword label is still navigation")
  func noKeywordInsideNavBarIsNavigation() {
    let button = AXNodeBuilder.button("Settings", at: (350, 22))
    let navBar = AXNodeBuilder.node(
      role: "AXNavigationBar",
      x: 0, y: 0, width: 393, height: 44, depth: 2,
      children: [button]
    )
    let tree = AXNodeBuilder.screenContent(children: [navBar])
    let analysis = ScreenAnalyzer.analyze(tree)

    #expect(analysis.navigation.count == 1)
    #expect(analysis.navigation[0].name == "Settings")
  }

  @Test("'Back' button far from top (y >= 100) is classified as action, not navigation")
  func backFarFromTopIsAction() {
    // Center at y=500 — too far down to be a nav button
    let tree = screenWithButton("Back", at: (196, 500))
    let analysis = ScreenAnalyzer.analyze(tree)

    #expect(analysis.navigation.isEmpty)
    #expect(analysis.actions.count == 1)
  }

  // MARK: - Disabled classification

  @Test("Disabled button is classified as disabled")
  func disabledIsDisabled() {
    let button = AXNodeBuilder.button("Submit", at: (196, 400), enabled: false)
    let tree = AXNodeBuilder.screenContent(children: [button])
    let analysis = ScreenAnalyzer.analyze(tree)

    #expect(analysis.disabled.count == 1)
    #expect(analysis.disabled[0].name == "Submit")
    #expect(analysis.actions.isEmpty)
  }

  // MARK: - Tab extraction

  @Test("Tabs are extracted from AXTabGroup children")
  func extractsTabs() {
    let tabGroup = AXNodeBuilder.tabGroup(
      tabs: [("Home", true), ("Schedule", false), ("Profile", false)]
    )
    let tree = AXNodeBuilder.screenContent(children: [tabGroup])
    let analysis = ScreenAnalyzer.analyze(tree)

    #expect(analysis.tabs.count == 3)
    #expect(analysis.tabs[0].label == "Home")
    #expect(analysis.tabs[1].label == "Schedule")
    #expect(analysis.tabs[2].label == "Profile")
  }

  @Test("Selected tab has isSelected=true")
  func tabSelectionState() {
    let tabGroup = AXNodeBuilder.tabGroup(
      tabs: [("Home", true), ("Schedule", false)]
    )
    let tree = AXNodeBuilder.screenContent(children: [tabGroup])
    let analysis = ScreenAnalyzer.analyze(tree)

    #expect(analysis.tabs[0].isSelected == true)
    #expect(analysis.tabs[1].isSelected == false)
  }

  // MARK: - Screen name inference

  @Test("Screen name inferred from top static text")
  func screenNameFromTopText() {
    let title = AXNodeBuilder.text("Welcome", at: (0, 60), size: (393, 30))
    let button = AXNodeBuilder.button("Sign In", at: (196, 400))
    let tree = AXNodeBuilder.screenContent(children: [title, button])
    let analysis = ScreenAnalyzer.analyze(tree)

    #expect(analysis.screenName == "Welcome")
  }

  @Test("Screen name from AXNavigationBar label")
  func screenNameFromNavBarLabel() {
    let navBar = AXNodeBuilder.navigationBar(title: "Settings")
    let button = AXNodeBuilder.button("Toggle", at: (196, 400))
    let tree = AXNodeBuilder.screenContent(children: [navBar, button])
    let analysis = ScreenAnalyzer.analyze(tree)

    #expect(analysis.screenName == "Settings")
  }

  @Test("Screen name from AXNavigationBar child AXStaticText")
  func screenNameFromNavBarChildText() {
    let titleText = AXNodeBuilder.text("Profile", at: (196, 22), size: (200, 20), depth: 3)
    let navBar = AXNodeBuilder.navigationBar(children: [titleText])
    let button = AXNodeBuilder.button("Edit", at: (196, 400))
    let tree = AXNodeBuilder.screenContent(children: [navBar, button])
    let analysis = ScreenAnalyzer.analyze(tree)

    #expect(analysis.screenName == "Profile")
  }

  @Test("Empty nav bar falls through to existing Strategy 1")
  func emptyNavBarFallsThrough() {
    let navBar = AXNodeBuilder.navigationBar()
    let title = AXNodeBuilder.text("Welcome", at: (0, 60), size: (393, 30))
    let tree = AXNodeBuilder.screenContent(children: [navBar, title])
    let analysis = ScreenAnalyzer.analyze(tree)

    #expect(analysis.screenName == "Welcome")
  }

  @Test("Nav bar title wins over top text")
  func navBarWinsOverTopText() {
    let navBar = AXNodeBuilder.navigationBar(title: "Settings")
    let topText = AXNodeBuilder.text("Feb 22, 2026", at: (0, 60), size: (393, 30))
    let tree = AXNodeBuilder.screenContent(children: [navBar, topText])
    let analysis = ScreenAnalyzer.analyze(tree)

    #expect(analysis.screenName == "Settings")
  }

  @Test("Screen name falls back to 'Unknown Screen' when no text exists")
  func screenNameUnknown() {
    let button = AXNodeBuilder.button("Tap Me", at: (196, 400))
    let tree = AXNodeBuilder.screenContent(children: [button])
    let analysis = ScreenAnalyzer.analyze(tree)

    #expect(analysis.screenName == "Unknown Screen")
  }

  // MARK: - Content extraction

  @Test("Content extracts AXStaticText elements")
  func extractsContent() {
    let text1 = AXNodeBuilder.text("Welcome back", at: (0, 100))
    let text2 = AXNodeBuilder.text("Your next appointment", at: (0, 150))
    let tree = AXNodeBuilder.screenContent(children: [text1, text2])
    let analysis = ScreenAnalyzer.analyze(tree)

    #expect(analysis.content.count == 2)
    #expect(analysis.content[0].text == "Welcome back" || analysis.content[1].text == "Welcome back")
  }

  @Test("Content is capped at 20 elements")
  func contentCapped() {
    let texts = (0..<30).map { i in
      AXNodeBuilder.text("Line \(i)", at: (0, Double(i) * 25))
    }
    let tree = AXNodeBuilder.screenContent(children: texts)
    let analysis = ScreenAnalyzer.analyze(tree)

    #expect(analysis.content.count == 20)
  }

  // MARK: - Suggested actions

  @Test("Scroll-down suggested when screen height > 900")
  func scrollSuggested() {
    let button = AXNodeBuilder.button("Action", at: (196, 500))
    let tree = AXNodeBuilder.screenContent(size: (393, 950), children: [button])
    let analysis = ScreenAnalyzer.analyze(tree)

    let scrollSuggestion = analysis.suggestedActions.first { $0.action == "scroll-down" }
    #expect(scrollSuggestion != nil)
    #expect(scrollSuggestion?.priority == 1) // scroll is highest priority
  }

  @Test("Action elements appear as tap suggestions")
  func actionsSuggested() {
    let button = AXNodeBuilder.button("Continue", at: (196, 400))
    let tree = AXNodeBuilder.screenContent(children: [button])
    let analysis = ScreenAnalyzer.analyze(tree)

    let tapSuggestion = analysis.suggestedActions.first { $0.action == "tap" }
    #expect(tapSuggestion != nil)
    #expect(tapSuggestion?.target == "Continue")
  }

  @Test("Unselected tabs appear as tap-tab suggestions")
  func unselectedTabsSuggested() {
    let tabGroup = AXNodeBuilder.tabGroup(
      tabs: [("Home", true), ("Schedule", false)]
    )
    let tree = AXNodeBuilder.screenContent(children: [tabGroup])
    let analysis = ScreenAnalyzer.analyze(tree)

    let tabSuggestion = analysis.suggestedActions.first { $0.action == "tap-tab" }
    #expect(tabSuggestion != nil)
    #expect(tabSuggestion?.target == "Schedule")
  }

  // MARK: - Element counts

  @Test("interactiveCount matches number of interactive elements")
  func interactiveCount() {
    let button = AXNodeBuilder.button("A", at: (100, 400))
    let link = AXNodeBuilder.link("B", at: (200, 400))
    let text = AXNodeBuilder.text("C", at: (0, 100))
    let tree = AXNodeBuilder.screenContent(children: [button, link, text])
    let analysis = ScreenAnalyzer.analyze(tree)

    #expect(analysis.interactiveCount == 2) // button + link
  }

  @Test("elementCount includes all nodes in tree")
  func elementCount() {
    let button = AXNodeBuilder.button("A", at: (100, 400))
    let text = AXNodeBuilder.text("B", at: (0, 100))
    let tree = AXNodeBuilder.screenContent(children: [button, text])
    let analysis = ScreenAnalyzer.analyze(tree)

    #expect(analysis.elementCount == 3) // screen group + button + text
  }

  // MARK: - containsCenter boundary

  @Test("Button below nav bar is classified as action even when nav bar exists")
  func buttonBelowNavBarIsAction() {
    let navButton = AXNodeBuilder.button("Back", at: (30, 22))
    let navBar = AXNodeBuilder.node(
      role: "AXNavigationBar",
      x: 0, y: 0, width: 393, height: 44, depth: 2,
      children: [navButton]
    )
    let actionButton = AXNodeBuilder.button("Submit", at: (196, 400))
    let tree = AXNodeBuilder.screenContent(children: [navBar, actionButton])
    let analysis = ScreenAnalyzer.analyze(tree)

    #expect(analysis.navigation.count == 1)
    #expect(analysis.navigation[0].name == "Back")
    #expect(analysis.actions.count == 1)
    #expect(analysis.actions[0].name == "Submit")
  }

  // MARK: - Screen name Strategy 1 and 2 boundaries

  @Test("Strategy 1 picks widest text among top elements")
  func strategy1PicksWidestTopText() {
    // Two texts near top, different widths, no nav bar
    let narrow = AXNodeBuilder.text("Narrow", at: (0, 60), size: (100, 20))
    let wide = AXNodeBuilder.text("Wide Title", at: (0, 80), size: (300, 20))
    let button = AXNodeBuilder.button("Tap", at: (196, 400))
    let tree = AXNodeBuilder.screenContent(children: [narrow, wide, button])
    let analysis = ScreenAnalyzer.analyze(tree)

    #expect(analysis.screenName == "Wide Title")
  }

  @Test("Strategy 2 picks topmost large text when no top texts exist")
  func strategy2PicksTopmostLargeText() {
    // Both texts below y=120, both height > 24, no nav bar
    let lower = AXNodeBuilder.text("Lower", at: (0, 300), size: (200, 30))
    let upper = AXNodeBuilder.text("Upper", at: (0, 200), size: (200, 30))
    let button = AXNodeBuilder.button("Tap", at: (196, 500))
    let tree = AXNodeBuilder.screenContent(children: [lower, upper, button])
    let analysis = ScreenAnalyzer.analyze(tree)

    #expect(analysis.screenName == "Upper")
  }

  @Test("Nav bar with button and text children uses text for screen name")
  func navBarWithMixedChildrenUsesText() {
    let editButton = AXNodeBuilder.button("Edit", at: (350, 22))
    let titleText = AXNodeBuilder.text("Profile", at: (196, 22), size: (200, 20), depth: 3)
    let navBar = AXNodeBuilder.navigationBar(children: [editButton, titleText])
    let button = AXNodeBuilder.button("Save", at: (196, 400))
    let tree = AXNodeBuilder.screenContent(children: [navBar, button])
    let analysis = ScreenAnalyzer.analyze(tree)

    #expect(analysis.screenName == "Profile")
  }

  // MARK: - Suggestion priority ordering

  @Test("Suggestion priorities are sequential — no duplicates")
  func suggestionPrioritiesSequential() {
    let button1 = AXNodeBuilder.button("Action 1", at: (196, 400))
    let button2 = AXNodeBuilder.button("Action 2", at: (196, 500))
    let tabGroup = AXNodeBuilder.tabGroup(tabs: [("Home", true), ("Profile", false)])
    let tree = AXNodeBuilder.screenContent(size: (393, 950), children: [button1, button2, tabGroup])
    let analysis = ScreenAnalyzer.analyze(tree)

    // Should have: scroll(1), tap Action 1(2), tap Action 2(3), tap-tab Profile(4+)
    let priorities = analysis.suggestedActions.map(\.priority)
    let uniquePriorities = Set(priorities)
    #expect(uniquePriorities.count == priorities.count, "Priorities must be unique: \(priorities)")
    // Verify sequential ordering
    for i in 1..<priorities.count {
      #expect(priorities[i] > priorities[i - 1])
    }
  }

  // MARK: - System UI Overlay Detection

  @Test("Minimal tree with time-like screen name triggers system UI warning")
  func systemUIOverlayWithTimeName() {
    // Simulate a screen with only a status bar time label and no interactive elements
    let timeText = AXNodeBuilder.text("9:41", at: (196, 10), size: (50, 20))
    let tree = AXNodeBuilder.screenContent(children: [timeText])
    let analysis = ScreenAnalyzer.analyze(tree)

    #expect(analysis.warning != nil)
    #expect(analysis.warning?.contains("System UI overlay detected") == true)
    #expect(analysis.warning?.contains("9:41") == true)
  }

  @Test("Minimal tree with no interactive elements triggers possible overlay warning")
  func systemUIOverlayMinimalTree() {
    // A few static texts, no buttons — like a system dialog blocking the app
    let text1 = AXNodeBuilder.text("Loading", at: (196, 400), size: (100, 20))
    let tree = AXNodeBuilder.screenContent(children: [text1])
    let analysis = ScreenAnalyzer.analyze(tree)

    #expect(analysis.warning != nil)
    #expect(analysis.warning?.contains("Possible system UI overlay") == true)
  }

  @Test("Normal screen with interactive elements has no warning")
  func normalScreenNoWarning() {
    let button = AXNodeBuilder.button("Continue", at: (196, 400))
    let text = AXNodeBuilder.text("Welcome", at: (0, 60), size: (393, 30))
    let tree = AXNodeBuilder.screenContent(children: [text, button])
    let analysis = ScreenAnalyzer.analyze(tree)

    #expect(analysis.warning == nil)
  }

  @Test("Content-only screen with many elements has no warning")
  func contentOnlyManyElementsNoWarning() {
    // 6+ elements but no buttons — warning should not trigger (elementCount >= 5)
    let texts = (0..<6).map { i in
      AXNodeBuilder.text("Line \(i)", at: (0, Double(i) * 30 + 100), size: (300, 20))
    }
    let tree = AXNodeBuilder.screenContent(children: texts)
    let analysis = ScreenAnalyzer.analyze(tree)

    #expect(analysis.warning == nil)
  }

  // MARK: - Helpers

  private func screenWithButton(
    _ label: String, at center: (Double, Double), enabled: Bool = true
  ) -> AXNode {
    let button = AXNodeBuilder.button(label, at: center, enabled: enabled)
    return AXNodeBuilder.screenContent(children: [button])
  }
}
