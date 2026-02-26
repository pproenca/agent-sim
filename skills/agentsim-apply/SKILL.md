---
name: agentsim-apply
description: "Apply findings from a sweep — fix accessibility gaps, file bug reports"
---


Apply findings from a completed (or in-progress) exploration sweep.
Read the journal, categorize what was found, fix what can be fixed, report what can't.

**Input**: Optionally specify what to apply (e.g., `/agentsim:apply fix accessibility`, `/agentsim:apply bug reports`). If omitted, analyze all findings and ask.

> Looking to generate XCTest cases? Use `/agentsim:replay generate tests` instead — it replays scenarios and converts passing ones to XCTests.

---

## Path Resolution

```bash
JOURNALS=$(agent-sim config journals)
JOURNAL="$JOURNALS/sweep-journal.md"
```

---

## Step 1 — Load the journal

Check `$JOURNAL`. If not found, check `$JOURNALS/archive/` for recent sweeps.

Always announce: "Using sweep: \<scope\>" and the journal path.

```bash
agent-sim journal summary --path "$JOURNAL"
```

Read the full journal to extract:
- **Issues**: crashes, wrong navigation, stuck elements, missing content
- **Accessibility gaps**: elements without labels or identifiers
- **Screen coverage**: which screens were visited, which were not reached

---

## Step 2 — Categorize findings

| Category | Examples | Action |
|----------|----------|--------|
| Crashes | App terminated on tap | Bug report + investigation |
| Navigation bugs | Back went to wrong screen | Bug report + fix |
| Accessibility gaps | Button without label | Add accessibility identifier + VoiceOver label |
| Missing content | Expected element absent | Investigation |
| Stuck elements | Tap did nothing | Bug report + investigation |
| Coverage gaps | Screens never reached | Note for next sweep |

---

## Step 3 — Ask what to apply

Display finding count by category, priority-ordered (crashes > a11y gaps > nav bugs > coverage).

Use **AskUserQuestion**:
- Fix accessibility gaps (add missing identifiers and labels)
- Create bug reports for issues found
- All of the above

---

## Step 4 — Apply (loop until done or blocked)

**Fix accessibility gaps:**
- For each element missing an identifier, search the codebase for the view
- Add an accessibility identifier following the project's existing conventions
- Add VoiceOver labels where missing
- Keep changes minimal — only accessibility additions, no refactoring

**Create bug reports:**
- Use the issue report template at `$(agent-sim config root)/Templates/issue-report.md`
- Include reproduction steps from the journal entries (the BDD scenario)
- Include screenshots if captured during the sweep
- Write to `$JOURNALS/issues/`

**Pause if:**
- Finding is unclear → ask for clarification
- Fix requires architectural change → suggest investigation, not a quick fix
- Error or blocker → report and wait

---

## Step 5 — Report

```
## Findings Applied

**Sweep:** <scope>
**Journal:** <journal-path>
**Progress:** N/M findings addressed

### Applied
- [x] Fixed N accessibility gaps
- [x] Created N bug reports

### Remaining
- [ ] N findings need deeper investigation

Next: `/agentsim:replay` to verify fixes, `/agentsim:new` for a fresh sweep.
```

---

## Guardrails

- Always read the journal before applying — never fabricate findings
- Keep code changes minimal and focused (a11y fixes only, not refactors)
- Follow the project's existing accessibility conventions
- Bug reports include reproduction steps from the journal — never fabricate steps
- If finding is ambiguous, pause and ask before acting
- Pause on errors, blockers, or unclear findings — don't guess
