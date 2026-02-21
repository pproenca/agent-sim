# Issue Report

<!-- Generated when the agent detects unexpected behavior during exploration. -->

## Issue #{number}

- **Severity**: {crash | wrong-navigation | missing-element | visual-glitch | performance}
- **Discovered at**: Action #{action_index} in sweep journal
- **Screen**: {screen name} ({fingerprint[:8]})
- **Timestamp**: {ISO timestamp}

### What happened

{One sentence: what was done and what the expected vs actual outcome was.}

### Reproduction

1. Start from: {entry state}
2. Navigate to: {screen path, e.g., "Home > Find Session > Session Detail"}
3. Tap: "{element label}" at ({x}, {y})
4. **Expected**: {what should have happened}
5. **Actual**: {what actually happened}

### Evidence

- **Screenshot before**: {path}
- **Screenshot after**: {path}
- **Fingerprint before**: {hash}
- **Fingerprint after**: {hash}
- **Console log excerpt**: (if available)

```
{relevant log lines}
```

### Classification

- **Type**: {navigation-bug | crash | state-bug | accessibility-gap | visual-regression}
- **Affected flow**: {e.g., "Booking flow", "Profile settings"}
- **Suspected module**: {e.g., "FeatureSchedule", "CalendarCoordinator"}

---

<!-- Repeat for each issue found -->
