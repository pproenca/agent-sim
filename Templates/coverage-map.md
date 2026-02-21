# Coverage Map

<!-- Generated after a sweep completes. Shows what was reached and what was missed. -->

## Screens Visited

| # | Screen Name | Fingerprint | Depth | Elements Tapped | Elements Skipped | Issues |
|---|-------------|-------------|-------|-----------------|------------------|--------|
| 1 | {name} | {hash[:8]} | 0 | {count} | {count} | {0 or details} |

## Navigation Graph

<!-- Text representation of the screen graph discovered during traversal -->

```
{Tab: Home} (depth 0)
├── {Screen A} (depth 1)
│   ├── {Screen B} (depth 2)
│   └── {Screen C} (depth 2)
└── {Screen D} (depth 1)

{Tab: Schedule} (depth 0)
├── ...
```

## Unreached Areas

| Area | Reason | How to reach |
|------|--------|--------------|
| {screen/flow} | {e.g., "Behind auth wall"} | {e.g., "Log in first"} |
| {screen/flow} | {e.g., "Requires booking data"} | {e.g., "Create a session first"} |

## Element Coverage by Screen

### {Screen Name} ({fingerprint[:8]})

- **Tapped**: {label1}, {label2}, {label3}
- **Skipped (destructive)**: {label}
- **Skipped (disabled)**: {label}
- **Not reached (depth limit)**: {label}
