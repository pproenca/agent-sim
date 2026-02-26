---
name: agentsim-tests
description: "Turn sweep journal into tests — analyze scenarios, choose the right test level, generate code"
---


Convert observations from a sweep journal into permanent tests. Every journal entry is a
candidate — but not every observation belongs at the same level of the testing pyramid.
This command analyzes each scenario, discusses placement with the user, and generates
tests that follow the project's established patterns.

**Input**: Optionally specify scope (e.g., `/agentsim:tests onboarding`, `/agentsim:tests all`). Defaults to all scenarios from the most recent journal.

> This command generates tests from *observed behavior*. Use `/agentsim:replay` first to verify scenarios still pass before generating permanent tests.

---

## Path Resolution

```bash
JOURNALS=$(agent-sim config journals)
JOURNAL="$JOURNALS/sweep-journal.md"
```

---

## Step 1 — Load and parse the journal

Check `$JOURNAL`. If not found, check `$JOURNALS/archive/` for recent sweeps.

If multiple journals exist, use **AskUserQuestion** to select.

```bash
agent-sim journal summary --path "$JOURNAL"
```

Read the full journal. Parse every entry into a scenario:

```
Scenario #N: <target>
  Given: screen "<before-name>" (fingerprint: <before>)
  When:  <action> "<target>" at (<x>, <y>)
  Then:  screen "<after-name>" (fingerprint: <after>)
  Issue: <issue or none>
  Result: <navigated | same-screen | crash | error>
```

Announce: "Loaded N scenarios from sweep: \<scope\>"

---

## Step 2 — Read the existing test suite

Before proposing any tests, understand what already exists. Read:

1. **E2E tests** — `mobile/MaddieAppNativeE2ETests/Tests/` for page objects, existing journeys, `BaseE2ETestCase`
2. **Unit tests** — `mobile/MaddieAppNativeLogicTests/` for ViewModel tests, test doubles, integration tests
3. **Package tests** — `mobile/Packages/Tests/` for repository/service/domain tests
4. **Test infrastructure** — `mobile/App/Testing/` for `UITestLaunchConfiguration`, `LaunchArgumentBuilder`
5. **Accessibility IDs** — `mobile/Packages/SharedKit/Sources/AccessibilityID.swift`

Check which scenarios already have test coverage. Don't duplicate existing tests.

---

## Step 3 — Classify each scenario

For each journal entry, classify where in the testing pyramid it belongs:

### Classification rules

| Observation type | Test level | Rationale |
|---|---|---|
| **Screen-to-screen navigation** (tap X → new screen appears) | **E2E** | Tests the full navigation stack, coordinator wiring, view lifecycle |
| **Tab bar navigation** (tap tab → correct screen) | **E2E** | Tests tab coordinator and root navigation |
| **Form submission with result** (fill + submit → success/error) | **E2E** | Tests the full form flow including API interaction |
| **Element visibility/state** (button enabled/disabled, text displayed) | **Unit (ViewModel)** | ViewModel controls what's shown — test the ViewModel, not the view |
| **Data loading behavior** (screen loads → shows cached data → refreshes) | **Unit (ViewModel)** | Stale-while-revalidate is ViewModel logic |
| **Error states** (network error → error message shown) | **Unit (ViewModel)** | Error handling is ViewModel responsibility |
| **Modal/sheet presentation** (tap → sheet appears) | **Unit (Coordinator)** | Coordinator decides presentation — test the coordinator |
| **Data transformation** (API response → displayed format) | **Package (Repository/Service)** | Data mapping lives in the Data layer |
| **Validation logic** (invalid input → rejection) | **Package (Domain)** | Validation belongs in domain models |
| **Crash on action** | **Bug report, not a test** | Fix the crash first, then add a regression test |
| **Accessibility gap** (missing label/identifier) | **Not a test** — fix via `/agentsim:apply` | A11y fixes are code changes, not test scenarios |
| **Same-screen, no effect** (tap → nothing happened) | **Skip** | Likely a non-interactive element or timing issue |

### What NOT to test

Skip scenarios that:
- Are already covered by existing tests (check Step 2)
- Are pure navigation scaffolding with no business logic (e.g., tab switching when tabs are hardcoded)
- Represent timing issues or flaky simulator behavior
- Would create brittle tests coupled to layout details

### Grouping

Group related scenarios into logical test cases:
- Multiple taps on the same screen → one test per meaningful behavior
- Sequential navigation (A → B → C) → one E2E journey test, not three separate tests
- Same pattern across screens (e.g., "back button works") → one parameterized test or skip if trivial

---

## Step 4 — Present the plan

Show the classification to the user as a table:

```
## Test Plan from Sweep: <scope>

**Scenarios analyzed:** N
**Tests proposed:** M (E unit, F E2E, G package)
**Skipped:** K (already covered, not testable, accessibility fixes)

### E2E Tests (X scenarios → Y test methods)

| # | Scenario | Proposed test | File |
|---|----------|--------------|------|
| 1,2,3 | Onboarding flow: Welcome → Step 1 → Step 2 → Complete | `testOnboardingFlowCompletesAllSteps()` | `OnboardingE2ETests.swift` |
| 5,8 | Booking: Home → Calendar → Slots → Checkout | `testBookingFlowFromHomeToCheckout()` | `BookingJourneyE2ETests.swift` |

### Unit Tests (X scenarios → Y test methods)

| # | Scenario | Proposed test | File |
|---|----------|--------------|------|
| 4 | Error banner appears when session load fails | `testLoadSessionFailureShowsError()` | `SessionDetailViewModelTests.swift` |

### Package Tests (X scenarios → Y test methods)

| # | Scenario | Proposed test | File |
|---|----------|--------------|------|
| 7 | Treatment list sorted by name | `testFetchTreatmentsSortsByName()` | `DefaultBookingRepositoryTests.swift` |

### Skipped

| # | Reason |
|---|--------|
| 6 | Already covered by `testBackNavigatesToParent()` |
| 9 | Accessibility gap — use `/agentsim:apply` instead |
| 10 | Same-screen no-op (timing issue) |
```

Use **AskUserQuestion** to let the user adjust:
- "Generate all proposed tests"
- "Let me pick which ones to generate"
- "Adjust classifications first"

If the user picks "Let me pick", show checkboxes per test.
If the user picks "Adjust classifications", ask which scenarios to reclassify and where.

---

## Step 5 — Generate tests

For each approved test, generate code following the project's exact conventions.

### E2E test conventions

```swift
// File: mobile/MaddieAppNativeE2ETests/Tests/<Feature>E2ETests.swift
import XCTest

final class <Feature>E2ETests: BaseE2ETestCase {

    func test<BehaviorDescription>() {
        launch(flow: .<appropriateFlow>)

        let page = <Page>(app: app).waitForScreen()
        page.<element>.tap()

        let nextPage = <NextPage>(app: app).waitForScreen()
        XCTAssertTrue(nextPage.<expectedElement>.exists)
    }
}
```

**Rules:**
- Inherit from `BaseE2ETestCase`
- Use `launch(flow:)` with the right flow from `LaunchArgumentBuilder`
- Use existing page objects — create new ones only if needed
- Page objects use `AccessibilityID` constants
- `waitForScreen()` before interacting with a new page
- Test names describe behavior: `testFeatureScenarioExpectedOutcome()`
- Merge into existing test classes when the feature already has one

### Unit test conventions (ViewModel)

```swift
// File: mobile/MaddieAppNativeLogicTests/<Feature>/<ViewModel>Tests.swift
import XCTest
@testable import MaddieAppNative

@MainActor
final class <ViewModel>Tests: XCTestCase {

    func test<BehaviorDescription>() async {
        let sut = makeSUT()

        await sut.<action>()

        XCTAssertEqual(sut.<property>, <expected>)
    }

    private func makeSUT(
        // injectable dependencies with defaults
    ) -> <ViewModel> {
        <ViewModel>(/* ... */)
    }
}
```

**Rules:**
- `@MainActor` on test class (for @Observable ViewModels)
- `sut` convention for system under test
- Private `makeSUT()` factory with sensible defaults
- Protocol-based test doubles (no mocking frameworks)
- Test doubles as private types at bottom of file or in shared Support/
- `async` test methods for async behavior

### Package test conventions

```swift
// File: mobile/Packages/Tests/<Module>Tests/<Type>Tests.swift
import XCTest
@testable import <Module>

@MainActor
final class <Type>Tests: XCTestCase {

    func test<BehaviorDescription>() async throws {
        let sut = <Type>(/* closure injection or protocol doubles */)

        let result = try await sut.<method>(/* args */)

        XCTAssertEqual(result, <expected>)
    }
}

// Private helpers at bottom
private func make<Thing>(/* overrides */) -> <Thing> { /* ... */ }
```

**Rules:**
- Closure injection for simple dependencies
- Private helper factories as module-level functions
- Test edge cases: empty strings, whitespace, nil, zero values
- No simulator needed — pure Swift

### Creating page objects (E2E only, when needed)

If a scenario requires a page object that doesn't exist:

```swift
// File: mobile/MaddieAppNativeE2ETests/Pages/<Screen>Page.swift
import XCTest

struct <Screen>Page {
    let app: XCUIApplication

    var <element>: XCUIElement {
        app.buttons[AccessibilityID.<Feature>.<element>]
    }

    @discardableResult
    func waitForScreen(timeout: TimeInterval = 10) -> Self {
        XCTAssertTrue(
            app.descendants(matching: .any)[AccessibilityID.Screen.<screen>]
                .firstMatch.waitForExistence(timeout: timeout),
            "<Screen> screen did not appear"
        )
        return self
    }
}
```

Check if the necessary `AccessibilityID` constants exist. If not, add them to `mobile/Packages/SharedKit/Sources/AccessibilityID.swift` and add the corresponding `.accessibilityIdentifier()` modifiers to the SwiftUI views.

### Creating test doubles (unit tests only, when needed)

If a test needs a double that doesn't exist:

```swift
// Spy — records calls for verification
@MainActor
private final class Spy<Protocol>: <Protocol> {
    private(set) var <method>CallCount = 0
    private(set) var last<Param>: <Type>?

    func <method>(<params>) async throws -> <Return> {
        <method>CallCount += 1
        last<Param> = <param>
        return <defaultValue>
    }
}

// Stub — returns configured values
@MainActor
private final class Stub<Protocol>: <Protocol> {
    var <method>Result: Result<<Return>, Error> = .success(<default>)

    func <method>(<params>) async throws -> <Return> {
        try <method>Result.get()
    }
}
```

---

## Step 6 — Verify tests compile

After generating all test files:

1. **Check the right test tier compiles:**

   | Test level | Verify command |
   |---|---|
   | Package tests | `cd mobile && swift build --package-path Packages` |
   | Unit tests | `cd mobile && xcodebuild build-for-testing -scheme MaddieAppNative-Unit -destination 'platform=iOS Simulator,name=iPhone 16' -skipMacroValidation 2>&1 \| tail -20` |
   | E2E tests | `cd mobile && xcodebuild build-for-testing -scheme MaddieAppNative-E2E -destination 'platform=iOS Simulator,name=iPhone 16' -skipMacroValidation 2>&1 \| tail -20` |

2. **Fix compilation errors** before reporting.

3. **Do NOT run the full test suite** — just verify compilation. The user decides when to run tests.

---

## Step 7 — Report

```
## Tests Generated from Sweep: <scope>

**Source journal:** <path>
**Scenarios analyzed:** N
**Tests generated:** M

### E2E Tests
- <File>: N test methods
  - `testOnboardingFlowCompletesAllSteps()`
  - `testBookingFlowFromHomeToCheckout()`

### Unit Tests
- <File>: N test methods
  - `testLoadSessionFailureShowsError()`

### Package Tests
- <File>: N test methods
  - `testFetchTreatmentsSortsByName()`

### New Infrastructure Created
- Page objects: <list or "none">
- Test doubles: <list or "none">
- AccessibilityIDs added: <list or "none">

### Verification
- [x] All tests compile
- [ ] Tests not yet run — verify with:
  - `mise run test-ios-package` (package tests)
  - `mise run test-ios-unit` (unit + package)
  - `mise run test-ios-e2e` (E2E)

### Skipped Scenarios
- N scenarios skipped (already covered, not testable, or need `/agentsim:apply` first)

Next: Run the appropriate test tier to verify. Use `/agentsim:replay` to re-run the sweep and validate.
```

---

## Guardrails

- **Read the test suite before generating** — match existing style exactly, merge into existing files
- **Never duplicate existing tests** — check coverage in Step 2
- **Test behavior, not implementation** — tests verify what *should* happen, not current broken behavior
- **Follow the testing pyramid** — prefer the lowest level that covers the scenario (package > unit > E2E)
- **Don't test everything** — skip no-ops, timing artifacts, and a11y gaps (those are code fixes)
- **Group related scenarios** — one journey test beats five fragmented navigation tests
- **Verify compilation** — never report success if tests don't compile
- **Don't run the full suite** — compilation check only, user decides when to run
- **Keep changes minimal** — only add infrastructure (page objects, doubles, IDs) when needed
- **Ask before generating** — the user approves the plan before any code is written
