# UX Review

<!-- Generated after a sweep. Not a checklist — opinionated analysis grounded in what was observed. -->

**Sweep scope**: {scope}
**Date**: {ISO date}
**Screens visited**: {N}
**Actions taken**: {M}

---

## 1. Discoverability & Tap Depth

<!-- Can users find key features? How many taps to reach critical actions?
     HIG anchors:
     - Designing for iOS: "discoverable with minimal interaction"
     - Layout: "Make essential information easy to find by giving it sufficient space" -->

{For each finding: what screen/flow you observed, how deep it was buried, why it matters, and a concrete fix. Skip this section if nothing was observed.}

---

## 2. Content Hierarchy & Surfacing

<!-- Does the app surface pending actions, state, and counts where users already are?
     HIG anchors:
     - Feedback: "Consider integrating status feedback into your interface... people get important information without having to take action or leave their current context"
     - Tab Bars: "Use a badge to indicate that critical information is available"
     - Layout: "Place items to convey their relative importance" -->

{Are pending items, counts, or status indicators visible on parent screens? Is important content above the fold or hidden behind scrolling/taps?}

---

## 3. Navigation Patterns

<!-- Do transitions match iOS conventions? Is modality used correctly?
     HIG anchors:
     - Tab Bars: "Make sure the tab bar is visible when people navigate"
     - Modality: "Present content modally only when there's a clear benefit"
     - Modality: "Avoid creating a modal experience that feels like an app within your app" -->

{Call out unexpected transitions, missing back buttons, hidden tab bars, overused modals, or inconsistent push/modal patterns.}

---

## 4. Feedback & Status Communication

<!-- Does the app communicate loading, success, failure, and current state?
     HIG anchors:
     - Feedback: "The most effective feedback tends to match the significance of the information to the way it's delivered"
     - Loading: "Show something as soon as possible"
     - Launching: "Restore the previous state when your app restarts" -->

{Were there silent failures, missing loading indicators, or actions with no confirmation? Does the app restore state on relaunch?}

---

## 5. Control Sizing & Ergonomics

<!-- Are tap targets comfortable? Are primary actions in the reach zone?
     HIG anchors:
     - Accessibility: "Default 44x44 pt, minimum 28x28 pt" and "Consider spacing between controls as important as size"
     - Designing for iOS: "easier and more comfortable for people to reach a control when it's located in the middle or bottom area of the display" -->

{Note undersized targets, cramped spacing, or primary actions placed in hard-to-reach areas (top corners on large screens).}

---

## 6. Progressive Disclosure

<!-- Is complexity managed? Are advanced features hidden until needed?
     HIG anchors:
     - Layout: "Take advantage of progressive disclosure to help people discover content that's currently hidden"
     - Disclosure Controls: "Place controls that people are most likely to use at the top of the disclosure hierarchy" -->

{Is the user overwhelmed on any screen? Are there screens that show too much at once, or conversely hide critical options too aggressively?}

---

## 7. Consistency

<!-- Internal consistency across screens, platform consistency with iOS conventions.
     HIG anchors:
     - Typography: "Minimize the number of typefaces... obscure information hierarchy"
     - Tab Bars: "Don't disable or hide tab bar buttons"
     - Accessibility/Cognitive: "Keep actions simple and intuitive... consistent interactions" -->

{Are similar actions styled differently across screens? Do controls behave inconsistently? Any platform convention violations?}

---

## Top 3 Recommendations

<!-- The most impactful changes ranked by user value. Each one should be specific and actionable. -->

| # | What | Why | Effort |
|---|------|-----|--------|
| 1 | {specific change} | {user impact} | {S/M/L} |
| 2 | {specific change} | {user impact} | {S/M/L} |
| 3 | {specific change} | {user impact} | {S/M/L} |
