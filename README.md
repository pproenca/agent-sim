# agent-sim

Simulator automation for AI agents. Tap, swipe, read accessibility trees, take screenshots — all without taking over your mouse.

Built on [FBSimulatorControl](https://github.com/facebook/idb) (Meta's IDB framework). Zero shell commands — every operation goes through the framework directly.

## Install

```bash
# Homebrew
brew install pproenca/tap/agent-sim

# or curl
curl -fsSL https://raw.githubusercontent.com/pproenca/agent-sim/main/scripts/install.sh | bash
```

### Requirements

- macOS (Apple Silicon)
- Xcode with at least one iOS Simulator runtime installed

## Quick start

```bash
# Boot a simulator
open -a Simulator

# Check status
agent-sim status

# Launch an app
agent-sim launch com.example.myapp

# See what's on screen
agent-sim explore --pretty

# Tap an element by label
agent-sim tap --label "Sign In"

# Take a screenshot
agent-sim screenshot

# Assert screen state
agent-sim assert --contains "Welcome" --screen-name "Home"
```

## Commands

| Command | What it does |
|---|---|
| `status` | Show booted simulators and active device |
| `explore` | Classify the current screen — actions, navigation, tabs, content |
| `describe` | Show the raw accessibility tree |
| `tap` | Tap an element by label, coordinates, or box number |
| `swipe` | Swipe up/down/left/right |
| `type` | Type text via HID keyboard events |
| `screenshot` | Capture the screen as PNG |
| `fingerprint` | Hash the current screen for change detection |
| `assert` | Verify screen state (exit 0 on pass, 1 on fail) |
| `launch` | Launch an app by bundle ID |
| `terminate` | Kill a running app |
| `network` | Show recent HTTP activity from CFNetwork logs |
| `next` | Get the next instruction for an automated QA sweep |
| `use` | Pin a specific simulator when multiple are booted |

## How it works

All interactions go through FBSimulatorControl's in-process APIs:

- **Taps/swipes/typing** → `FBSimulatorHID` (no CGEvent, no mouse takeover)
- **Accessibility tree** → `FBAccessibilityCommands` (native iOS coordinates)
- **Screenshots** → `FBScreenshotCommands`
- **App lifecycle** → `FBApplicationCommands`
- **Log queries** → `FBProcessSpawnCommands`
- **Device info** → `FBSimulatorSet` + `FBiOSTargetScreenInfo`

You can keep working in other apps while agent-sim runs.

## License

MIT
