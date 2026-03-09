---
name: agentsim-replay
description: "Replay BDD scenarios from a sweep journal — regression testing and XCTest generation"
---


Replay the scenarios recorded during a sweep. Every journal entry from `/agentsim:new`
maps to a Given/When/Then scenario — this command re-executes them and reports pass/fail.

Use this for:
- **Regression testing** — verify nothing broke after code changes
- **Fix verification** — confirm `/agentsim:apply` fixes work
- **Test generation** — convert passing scenarios into permanent XCTest cases

**Input**: Optionally specify scope (e.g., `/agentsim:replay all`, `/agentsim:replay onboarding`, `/agentsim:replay generate tests`). Defaults to replaying all scenarios from the most recent journal.

---

## Path Resolution

```bash
JOURNALS=$(agent-sim config journals)
JOURNAL="$JOURNALS/sweep-journal.md"
```

---

## Step 1 — Load the journal

Check `$JOURNAL`. If not found, check `$JOURNALS/archive/`.

If multiple journals exist, use **AskUserQuestion** to select.

Read the full journal. Parse every entry into a replayable scenario:

```
Scenario #N: <target element>
  Given: screen "<before-name>" (fingerprint: <before>)
  When:  <action> "<target>" at (<x>, <y>)
  Then:  screen "<after-name>" (fingerprint: <after>)
```

Announce: "Loaded N scenarios from sweep: \<scope\>"

---

## Step 2 — Ensure app is ready

```bash
agent-sim doctor
```

If not ready, launch the app using the bundle ID from the journal or from the project:
```bash
agent-sim launch <bundle-id>
agent-sim ui wait
```

---

## Step 3 — Replay loop

For each scenario in journal order:

### 3a. Verify we're on the right screen

```bash
agent-sim explore --fingerprint
```

Compare against the scenario's `Given` fingerprint. If we're on a different screen:

1. **Try the app's navigation to get there:**
   - If the target screen is a tab, tap the tab: `agent-sim tap --label "<tab name>"`
   - If we need to go back, tap back: `agent-sim tap --label "Back"`
   - If it's a root screen, stop and relaunch: `agent-sim stop <bundle-id> && agent-sim launch <bundle-id> && agent-sim ui wait`

2. **Verify again:**
   ```bash
   agent-sim ui assert visible "<before-name>"
   ```

3. **If still wrong, mark as SKIP** with reason "could not navigate to starting screen"

### 3b. Execute the action

```bash
agent-sim tap --label "<target>"
sleep 1
```

If the element can't be found by label (layout changed), fall back to coordinates:
```bash
agent-sim tap <x> <y>
sleep 1
```

### 3c. Verify outcome

```bash
agent-sim explore --fingerprint
agent-sim ui assert visible "<after-name>"
```

Compare against the scenario's `Then`:
- **PASS**: Screen matches expected outcome
- **FAIL**: Different screen, crash, or missing elements
- **DRIFT**: Screen name matches but fingerprint differs (cosmetic change — new elements or shifted layout)

### 3d. Report inline

```
#1 tap "Get Started" on Welcome → Onboarding        [PASS]
#2 tap "Next" on Onboarding → Step 2                 [PASS]
#3 tap "Back" on Step 2 → Onboarding                 [DRIFT] fingerprint changed
#4 tap "Profile" on Home → Profile                   [FAIL] got Settings instead
#5 tap "Sign Out" on Profile                         [SKIP] destructive
```

### Crash recovery

If the app crashes during replay:
1. `agent-sim screenshot $JOURNALS/replay-crash-<N>.png`
2. Mark the scenario as **FAIL** with reason "crash"
3. `agent-sim launch <bundle-id> && agent-sim ui wait`
4. Continue with the next scenario

---

## Step 4 — Results

```
## Replay Results

**Sweep:** <scope>
**Scenarios:** N total, P passed, F failed, D drifted, S skipped

### Failures
| # | Action | Expected | Got | Severity |
|---|--------|----------|-----|----------|
| 4 | tap "Profile" on Home | Profile | Settings | CRITICAL |

### Drift
| # | Action | Screen | Note |
|---|--------|--------|------|
| 3 | tap "Back" on Step 2 | Onboarding | New element added |

### Skipped
| # | Reason |
|---|--------|
| 5 | Destructive action |
```

---

## Step 5 — Generate XCTest cases (optional)

If the user asked to generate tests, or after a fully passing replay:

Use **AskUserQuestion**:
- "Generate XCTest cases from passing scenarios"
- "Just show results"

If generating:

1. **Read the project's existing test suite first** — understand the patterns, page objects, accessibility identifiers, and test infrastructure already in use.

2. **For each passing scenario, generate a test method** that follows the project's conventions:

   ```swift
   func testGetStartedNavigatesToOnboarding() throws {
     // Given: Welcome screen
     // When: tap "Get Started"
     // Then: Onboarding screen is visible
   }
   ```

3. **Match existing style exactly:**
   - Use the same test framework the project uses
   - Follow the project's page object pattern if one exists
   - Use existing accessibility identifier conventions
   - Merge into existing test classes when appropriate
   - Test names describe behavior

4. **Verify tests compile** before reporting success.

---

## Guardrails

- **Replay in order** — scenarios depend on navigation state from previous steps
- **Never modify the journal** — it's the source of truth
- **Soft matching** — fingerprint differs but screen name matches = DRIFT, not FAIL
- **Skip destructive actions** — never replay Delete, Sign Out, etc.
- **Recover from crashes** — screenshot, mark FAIL, relaunch, continue
- **Don't fabricate results** — if a scenario can't be replayed, mark SKIP with reason
- **Generated tests must compile** — verify before reporting success
- **Read the test suite first** — match existing style, merge into existing classes
