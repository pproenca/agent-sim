# agent-sim

Simulator automation for AI agents. Boot, install, tap, swipe, read accessibility trees, take screenshots — all without taking over your mouse.

Built on [FBSimulatorControl](https://github.com/facebook/idb) (Meta's IDB framework). Zero shell commands — every operation goes through the framework directly.

## Install

### Claude Code plugin (recommended)

Install directly from Claude Code:

```
/install agentsim from pproenca/agent-sim
```

This installs the commands, skills, and templates. You still need the CLI binary — install it with Homebrew or curl below.

### CLI binary

```bash
# Homebrew (installs CLI + registers Claude Code plugin)
brew install pproenca/tap/agent-sim

# or curl (installs to ~/.local + registers Claude Code plugin)
curl -fsSL https://raw.githubusercontent.com/pproenca/agent-sim/master/scripts/install.sh | bash
```

Both installers also register agent-sim as a Claude Code plugin automatically.

### Claude Code commands

After installation, these commands are available:

- `/agentsim:new` — Exploratory QA sweep
- `/agentsim:replay` — Replay BDD scenarios
- `/agentsim:apply` — Apply findings from a sweep
- `/agentsim:critique` — Apple HIG design critique
- `/agentsim:tests` — Generate tests from sweep journal

### Requirements

- macOS (Apple Silicon)
- Xcode with at least one iOS Simulator runtime installed

## Quick start

```bash
# Boot a simulator (waits until fully ready)
agent-sim boot "iPhone 16"

# Install your app
agent-sim install path/to/MyApp.app

# List installed apps (to find the bundle ID)
agent-sim apps --pretty

# Launch it
agent-sim launch com.example.myapp

# Wait until the app is interactive
agent-sim wait

# See what's on screen
agent-sim explore --pretty

# Tap an element by label
agent-sim tap --label "Sign In"

# Take a screenshot
agent-sim screenshot
```

## Commands

| Command | What it does |
|---|---|
| `boot` | Boot a simulator by name or UDID. Waits until usable. |
| `install` | Install a .app or .ipa onto the booted simulator |
| `apps` | List installed apps on the simulator |
| `wait` | Block until the simulator screen is ready for interaction |
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

- **Simulator boot** → `FBSimulatorLifecycleCommands` (waits until usable)
- **App install** → `FBApplicationCommands` (returns bundle ID)
- **Taps/swipes/typing** → `FBSimulatorHID` (no CGEvent, no mouse takeover)
- **Accessibility tree** → `FBAccessibilityCommands` (native iOS coordinates)
- **Screenshots** → `FBScreenshotCommands`
- **App lifecycle** → `FBApplicationCommands`
- **Log queries** → `FBProcessSpawnCommands`
- **Device info** → `FBSimulatorSet` + `FBiOSTargetScreenInfo`

You can keep working in other apps while agent-sim runs.

## License

MIT
