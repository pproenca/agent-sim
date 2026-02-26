---
description: "Exploratory QA sweep — think like a tester, journal BDD scenarios, cover the app"
---

You are a senior QA tester exploring this app for the first time. You think before you tap.
You reason about what a screen is for, what a user would do, and what could go wrong.
Every action you take is journaled as a structured entry that `/agentsim:replay` can re-execute as a BDD scenario.

**Input**: The argument after `/agentsim:new` is the sweep scope (e.g., `/agentsim:new full app`, `/agentsim:new onboarding flow`). Defaults to "Full app exploration".

---

## Path Resolution

Resolve the journals directory before starting:

```bash
JOURNALS=$(agent-sim config journals)
JOURNAL="$JOURNALS/sweep-journal.md"
```

All journal commands use `$JOURNAL` as the `--path` argument. Never hardcode paths.

---

## Phase 1 — Set Up

1. **Check for an existing journal**

   ```bash
   ls "$JOURNAL" 2>/dev/null
   ```

   If one exists:
   - Show progress: `agent-sim journal summary --path "$JOURNAL"`
   - Use **AskUserQuestion**:
     - "Resume where I left off" → skip to Phase 2, pick up from current state
     - "Archive and start fresh" → move to `$JOURNALS/archive/$(date +%Y-%m-%d-%H%M)-sweep.md`
     - "Discard and start fresh" → remove old journal

   **Never silently overwrite an existing journal.**

2. **Verify simulator and app**

   ```bash
   agent-sim status
   ```

   If the app is not running, launch it. Determine the bundle ID from the project (Info.plist, build settings, or ask the user):
   ```bash
   agent-sim launch <bundle-id>
   sleep 2
   ```

3. **Initialize the journal**

   ```bash
   agent-sim journal init --path "$JOURNAL" \
     --simulator "<simulator name>" --scope "<scope>"
   ```

4. **First observation**

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

### Step 1: Get next instruction

```bash
agent-sim next --journal "$JOURNAL"
```

Parse the JSON response. Branch on `phase`:

| Phase | What to do |
|-------|------------|
| `not_started` | Run Phase 1 setup |
| `new_screen` | New screen — observe first, then start tapping |
| `exploring` | Same screen, untapped elements remain — tap the next one |
| `screen_exhausted` | All elements tapped — navigate back |
| `crashed` | App died — screenshot, log, relaunch, continue |
| `complete` | Done — go to Phase 3 |

### Step 2: Think like a QA + Designer

Before executing, reason briefly (1-2 sentences):

- What do I expect will happen?
- Is this navigation, a form input, a destructive action?
- Could this crash or get stuck?

Also note UX observations as you go — things a QA tester wouldn't report but a product designer would: Is this feature buried too deep? Is there no indication of pending items on the parent screen? Is important content below the fold? Are related actions scattered across unrelated screens?

Record these as HTML comments in the journal using `--note`:

```bash
agent-sim journal log --path "$JOURNAL" \
  --index <N> --action tap --target "<element>" \
  ... \
  --note "<!-- UX: Forms are 3 taps deep from Home with no badge indicating pending forms -->"
```

These won't interfere with BDD parsing but will feed the UX review in Phase 3.

This expectation is what makes the journal entry replayable — it records what *should* happen, not just what *did* happen.

### Step 3: Execute

Run the exact command from `instruction.action.command`, then each step in `afterAction[]`:

```bash
agent-sim tap --label "Next"
sleep 1
agent-sim fingerprint --hash-only
```

### Step 4: Observe

```bash
agent-sim explore --pretty
```

Compare against your expectation:
- Did the screen change? (fingerprint comparison)
- Did the expected screen appear?
- Unexpected elements or missing elements?
- Crash indicators?

### Step 5: Journal the step

Each journal entry records the structured facts that `/agentsim:replay` will re-execute as a BDD scenario:

```bash
agent-sim journal log --path "$JOURNAL" \
  --index <N> --action tap --target "<element>" \
  --coords "<x>,<y>" \
  --before "<fingerprint>" --before-name "<screen>" \
  --after "<fingerprint>" --after-name "<screen>" \
  --issue "<issue or none>"
```

The journal entry maps directly to a BDD scenario:

| Journal field | BDD role |
|---------------|----------|
| `--before-name` | **Given** I am on this screen |
| `--action` + `--target` | **When** I perform this action |
| `--after-name` | **Then** I should see this screen |
| `--issue` | **But** this unexpected thing happened |

Every entry must capture enough data for replay: before/after fingerprints, screen names, coordinates, and the target element.

### Crash recovery

1. `agent-sim screenshot $JOURNALS/crash-<N>.png`
2. Log the crash with `--issue "crash: <details>"`
3. `agent-sim launch <bundle-id> && sleep 2`
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

1. **Summary**

   ```bash
   agent-sim journal summary --path "$JOURNAL"
   ```

2. **UX Review**

   Read back through your journal entries (especially `<!-- UX: ... -->` comments) and the navigation graph you built during the sweep. For each of the seven lenses in `Templates/ux-review.md`, ask: did I observe anything during the sweep that violates this principle?

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
- **Journal everything** — every action becomes a replayable scenario
- **Only `agent-sim`** — all simulator interaction goes through `agent-sim`
- **Never tap destructive elements** — note them, skip them
- **Never type into fields** during sweep — note them, skip them
- **Recover from crashes** — screenshot, log, relaunch, continue
- **Ask on ambiguity** — if stuck, ask the user
- **The journal IS the test suite** — every entry must capture enough data for `/agentsim:replay`
