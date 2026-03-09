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
# Homebrew (installs CLI)
brew install pproenca/tap/agent-sim

# or curl (installs to ~/.local/bin + ~/.local/lib/agent-sim)
curl -fsSL https://raw.githubusercontent.com/pproenca/agent-sim/master/scripts/install.sh | bash
```

The installer can register agent-sim assets for Claude Code and OpenCode in:

- `user` scope:
  - Claude: `~/.claude/skills/`
  - OpenCode: `~/.config/opencode/skills/` and `~/.config/opencode/commands/`
- `project` scope:
  - Claude: `.claude/skills/`
  - OpenCode: `.opencode/skills/` and `.opencode/commands/`

You can set scope non-interactively:

```bash
AGENT_SIM_SCOPE=user curl -fsSL https://raw.githubusercontent.com/pproenca/agent-sim/master/scripts/install.sh | bash
AGENT_SIM_SCOPE=project AGENT_SIM_PROJECT_DIR="$PWD" curl -fsSL https://raw.githubusercontent.com/pproenca/agent-sim/master/scripts/install.sh | bash
```

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
agent-sim sim boot "iPhone 16"

# Install your app
agent-sim sim install path/to/MyApp.app

# List installed apps (to find the bundle ID)
agent-sim sim apps --pretty

# Launch it
agent-sim launch com.example.myapp

# Wait until the app is interactive
agent-sim ui wait

# See what's on screen (interactive elements with @eN refs)
agent-sim explore -i

# Tap an element by ref
agent-sim tap @e3

# Tap an element by label
agent-sim tap --label "Sign In"

# Take a screenshot
agent-sim screenshot
```

## Commands

### Top-level

| Command | What it does |
|---|---|
| `explore` | Classify the current screen — actions, navigation, tabs, content |
| `explore -i` | List interactive elements with `@eN` refs |
| `explore --raw` | Show the raw accessibility tree |
| `explore --fingerprint` | Hash the current screen for change detection |
| `explore --diff` | Show what changed since last explore |
| `tap` | Tap an element by ref, label, coordinates, or box number |
| `swipe` | Swipe up/down/left/right |
| `type` | Type text via HID keyboard events |
| `screenshot` | Capture the screen as PNG |
| `launch` | Launch an app by bundle ID |
| `stop` | Stop a running app |
| `doctor` | Health check for simulator and accessibility |
| `update` | Update agent-sim to latest version |

### Simulator (`sim`)

| Command | What it does |
|---|---|
| `sim boot` | Boot a simulator by name or UDID. Waits until usable. |
| `sim list` | List available simulators |
| `sim shutdown` | Shut down the booted simulator |
| `sim install` | Install a .app or .ipa onto the booted simulator |
| `sim apps` | List installed apps on the simulator |

### UI verification (`ui`)

| Command | What it does |
|---|---|
| `ui assert visible` | Verify element exists on screen |
| `ui assert hidden` | Verify element is absent |
| `ui assert text` | Verify text content |
| `ui assert enabled` | Verify element is enabled |
| `ui wait` | Block until the simulator screen is ready for interaction |
| `ui find` | Find elements matching a query |

### Configuration (`config`)

| Command | What it does |
|---|---|
| `config set` | Save project settings |
| `config show` | Show current configuration |
| `project context` | Show project context |

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
