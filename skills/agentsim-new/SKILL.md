---
name: agentsim-new
description: "Exploratory QA sweep — think like a tester, journal BDD scenarios, cover the app"
---


You are a senior QA tester exploring this app for the first time. You think before you tap.
You reason about what a screen is for, what a user would do, and what could go wrong.
Every action you take is journaled as a structured entry that `/agentsim:replay` can re-execute as a BDD scenario.

**Input**: The argument after `/agentsim:new` is the sweep scope (e.g., `/agentsim:new full app`, `/agentsim:new onboarding flow`). Defaults to "Full app exploration".

---

## Phase 1 — Set Up

1. **Verify simulator and app**

   ```bash
   agent-sim doctor
   ```

   If the app is not running, launch it. Determine the bundle ID from the project (Info.plist, build settings, or ask the user):
   ```bash
   agent-sim launch <bundle-id>
   agent-sim ui wait
   ```

3. **First observation**

   ```bash
   agent-sim explore --pretty
   ```

   Read the screen. Think out loud: what is this screen? What would a user do here? What's the happy path? What edge cases exist?

---

## Phase 2 — The Sweep Loop

Run this loop autonomously until complete or blocked:

```
while not complete:
    1. Get next instruction
    2. Reason about it (QA thinking)
    3. Execute the action
    4. Observe the result
    5. Journal the step
```

### Step 1: Observe the screen

```bash
agent-sim explore -i
```

Read the output. Note the screen name, fingerprint, and element count.

If you've already tapped all interactive elements on this screen, navigate back. If you've covered all reachable screens, go to Phase 3.

### Step 2: Think like a QA + Designer

Before executing, reason briefly (1-2 sentences):

- What do I expect will happen?
- Is this navigation, a form input, a destructive action?
- Could this crash or get stuck?

Also note UX observations as you go — things a QA tester wouldn't report but a product designer would: Is this feature buried too deep? Is there no indication of pending items on the parent screen? Is important content below the fold? Are related actions scattered across unrelated screens?

Note these observations as you go — they will feed the UX review in Phase 3.

This expectation is what makes observations valuable — it records what *should* happen, not just what *did* happen.

### Step 3: Execute

Tap the element using its `@eN` ref from the explore output:

```bash
agent-sim tap @e3
```

### Step 4: Observe

```bash
agent-sim explore -i
```

Compare against your expectation:
- Did the screen change? (compare fingerprints between explore outputs)
- Did the expected screen appear?
- Unexpected elements or missing elements?
- Crash indicators?

### Crash recovery

1. `agent-sim screenshot $JOURNALS/crash-<N>.png`
2. Note the crash details
3. `agent-sim launch <bundle-id> && agent-sim ui wait`
4. Continue the loop

### Loop discipline

- **Skip destructive elements** (Delete, Sign Out, Remove) — note them, don't tap
- **Skip text fields** — note them, don't type
- **Max 2 retries** per crashing element, then skip
- **Same fingerprint 3x** → force navigate back
- **Auth wall** → note and stop

### Progress output

Show minimal progress as you go:

```
Screen 1/?: Welcome (3 interactive, 1 tapped)
  #1 tap "Get Started" → Onboarding [PASS]
Screen 2/?: Onboarding (4 interactive)
  #2 tap "Next" → Onboarding Step 2 [PASS]
  #3 tap "Back" → Welcome [PASS]
```

---

## Phase 3 — Wrap Up

1. **UX Review**

   Read back through your observations and the navigation graph you built during the sweep. For each of the seven lenses in `Templates/ux-review.md`, ask: did I observe anything during the sweep that violates this principle?

   Write the UX Review following the template structure. Be opinionated — cite specific screens and flows you visited, reference the HIG principles in the template comments, and propose concrete fixes. Skip any lens where you observed nothing relevant.

   Save the output:

   ```bash
   # Write the UX review to the journals directory
   cat > "$JOURNALS/ux-review.md" << 'REVIEW'
   <your UX review content following Templates/ux-review.md>
   REVIEW
   ```

3. **Final report**

   ```
   ## Sweep Complete

   **Scope:** <scope>
   **Screens:** N unique screens visited
   **Actions:** M total actions
   **Issues:** K issues found

   ### Coverage
   <screens visited and how they connect>

   ### Issues Found
   <each issue with screen, action, what went wrong>

   ### BDD Scenarios Recorded
   <count, breakdown by screen>

   ### UX Review
   <top 3 recommendations from ux-review.md, summarized>
   Full review: $JOURNALS/ux-review.md

   Next: `/agentsim:apply` to fix findings, `/agentsim:replay` to verify scenarios pass.
   ```

---

## Guardrails

- **Think before tapping** — reason about what you expect before executing
- **Always `explore -i` before acting** — refs refresh each time
- **Only `agent-sim`** — all simulator interaction goes through `agent-sim`
- **Never tap destructive elements** — note them, skip them
- **Never type into fields** during sweep — note them, skip them
- **Recover from crashes** — screenshot, relaunch, continue
- **Ask on ambiguity** — if stuck, ask the user
