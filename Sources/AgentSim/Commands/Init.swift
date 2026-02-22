import ArgumentParser
import Foundation

/// Initialize AgentSim in a project or at user scope.
///
/// Creates the config file, journals directory, and installs
/// agent commands for the configured tools (Claude Code, Cursor, etc.).
struct Init: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "init",
    abstract: "Initialize AgentSim. Creates config, journals directory, and installs agent commands."
  )

  @Option(name: .long, help: "Scope: 'project' (default) or 'user'.")
  var scope: String?

  @Option(
    name: .long,
    help: "Comma-separated agent tools to configure: claude, cursor, windsurf, or 'all'."
  )
  var tools: String?

  @Argument(help: "Target directory (default: current directory). Ignored for user scope.")
  var path: String?

  @Flag(name: .long, help: "Overwrite existing config without prompting.")
  var force = false

  func run() throws {
    let resolvedScope = try resolveScope()
    let resolvedTools = resolveTools()

    let configPath: String
    let journalsDir: String
    let projectRoot: String

    switch resolvedScope {
    case .project:
      projectRoot = path ?? FileManager.default.currentDirectoryPath
      let agentSimDir = (projectRoot as NSString).appendingPathComponent(".agent-sim")
      configPath = (agentSimDir as NSString).appendingPathComponent("config.json")
      journalsDir = (agentSimDir as NSString).appendingPathComponent("journals")

    case .user:
      let home = NSHomeDirectory()
      projectRoot = path ?? FileManager.default.currentDirectoryPath
      let agentSimDir = "\(home)/.config/agent-sim"
      configPath = "\(agentSimDir)/config.json"
      journalsDir = "\(agentSimDir)/journals"
    }

    // Check for existing config
    if FileManager.default.fileExists(atPath: configPath), !force {
      print("AgentSim already initialized at \(configPath)")
      print("Use --force to overwrite.")
      return
    }

    // Write config
    let config = ProjectConfig.Config(
      scope: resolvedScope,
      journals: resolvedScope == .project ? ".agent-sim/journals" : journalsDir
    )
    try ProjectConfig.write(config, to: configPath)

    // Create journals directory
    try FileManager.default.createDirectory(
      atPath: journalsDir, withIntermediateDirectories: true
    )

    // Install agent tool integrations
    let pluginRoot = ProjectConfig.pluginRoot()

    for tool in resolvedTools {
      switch tool {
      case "claude":
        try installClaude(projectRoot: projectRoot, pluginRoot: pluginRoot, scope: resolvedScope)
      case "cursor":
        try installCursor(projectRoot: projectRoot, pluginRoot: pluginRoot, scope: resolvedScope)
      case "windsurf":
        try installWindsurf(projectRoot: projectRoot, pluginRoot: pluginRoot, scope: resolvedScope)
      default:
        print("  Unknown tool: \(tool), skipping")
      }
    }

    // Summary
    print("")
    print("AgentSim initialized!")
    print("  Scope:    \(resolvedScope.rawValue)")
    print("  Config:   \(configPath)")
    print("  Journals: \(journalsDir)")
    if !resolvedTools.isEmpty {
      print("  Tools:    \(resolvedTools.joined(separator: ", "))")
    }
    print("")
    print("Commands available:")
    print("  /agentsim:new     — Start a QA sweep")
    print("  /agentsim:apply   — Fix findings")
    print("  /agentsim:replay  — Replay scenarios")
  }

  // MARK: - Scope Resolution

  private func resolveScope() throws -> ProjectConfig.Config.Scope {
    if let scope {
      guard let parsed = ProjectConfig.Config.Scope(rawValue: scope) else {
        throw InitError.invalidScope(scope)
      }
      return parsed
    }

    // Interactive: ask the user
    print("Where should AgentSim store its data?")
    print("")
    print("  1. project  — .agent-sim/ in this directory (recommended)")
    print("               Journals stay with the project. Committed or gitignored.")
    print("")
    print("  2. user     — ~/.config/agent-sim/")
    print("               Shared across all projects. Journals in your home directory.")
    print("")
    print("Scope [1/2] (default: 1): ", terminator: "")

    if let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty {
      switch input {
      case "2", "user":
        return .user
      default:
        return .project
      }
    }

    return .project
  }

  // MARK: - Tools Resolution

  private func resolveTools() -> [String] {
    if let tools {
      if tools == "all" {
        return ["claude", "cursor", "windsurf"]
      }
      if tools == "none" {
        return []
      }
      return tools.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
    }

    // Default to claude
    return ["claude"]
  }

  // MARK: - Tool Installation

  private func installClaude(
    projectRoot: String,
    pluginRoot: String?,
    scope: ProjectConfig.Config.Scope
  ) throws {
    let targetDir: String
    switch scope {
    case .project:
      targetDir = (projectRoot as NSString).appendingPathComponent(".claude/commands/agentsim")
    case .user:
      let home = NSHomeDirectory()
      targetDir = "\(home)/.claude/commands/agentsim"
    }

    try installCommands(to: targetDir, from: pluginRoot)
    print("  Claude Code: installed commands to \(targetDir)")
  }

  private func installCursor(
    projectRoot: String,
    pluginRoot: String?,
    scope: ProjectConfig.Config.Scope
  ) throws {
    let targetDir: String
    switch scope {
    case .project:
      targetDir = (projectRoot as NSString).appendingPathComponent(".cursor/rules")
    case .user:
      let home = NSHomeDirectory()
      targetDir = "\(home)/.cursor/rules"
    }

    try FileManager.default.createDirectory(
      atPath: targetDir, withIntermediateDirectories: true
    )

    // Generate a single rules file from the commands
    let rulesContent = generateCursorRules(from: pluginRoot)
    let rulesPath = (targetDir as NSString).appendingPathComponent("agentsim.mdc")
    try rulesContent.write(toFile: rulesPath, atomically: true, encoding: .utf8)
    print("  Cursor: installed rules to \(rulesPath)")
  }

  private func installWindsurf(
    projectRoot: String,
    pluginRoot: String?,
    scope: ProjectConfig.Config.Scope
  ) throws {
    let targetDir: String
    switch scope {
    case .project:
      targetDir = (projectRoot as NSString).appendingPathComponent(".windsurf/rules")
    case .user:
      let home = NSHomeDirectory()
      targetDir = "\(home)/.windsurf/rules"
    }

    try FileManager.default.createDirectory(
      atPath: targetDir, withIntermediateDirectories: true
    )

    let rulesContent = generateCursorRules(from: pluginRoot) // Same format works
    let rulesPath = (targetDir as NSString).appendingPathComponent("agentsim.md")
    try rulesContent.write(toFile: rulesPath, atomically: true, encoding: .utf8)
    print("  Windsurf: installed rules to \(rulesPath)")
  }

  // MARK: - Command Installation

  private func installCommands(to targetDir: String, from pluginRoot: String?) throws {
    let fm = FileManager.default
    try fm.createDirectory(atPath: targetDir, withIntermediateDirectories: true)

    guard let pluginRoot,
          fm.fileExists(atPath: (pluginRoot as NSString).appendingPathComponent("commands"))
    else {
      // No plugin root found — write minimal stubs
      for name in ["new", "apply", "replay"] {
        let stubPath = (targetDir as NSString).appendingPathComponent("\(name).md")
        if !fm.fileExists(atPath: stubPath) {
          let stub = """
            ---
            name: \(name)
            description: "AgentSim \(name) command — run `agent-sim --help` for details"
            ---
            Run `agent-sim \(name) --help` for usage.
            """
          try stub.write(toFile: stubPath, atomically: true, encoding: .utf8)
        }
      }
      return
    }

    // Copy command files from plugin root
    let commandsDir = (pluginRoot as NSString).appendingPathComponent("commands")
    let files = try fm.contentsOfDirectory(atPath: commandsDir)
    for file in files where file.hasSuffix(".md") {
      let src = (commandsDir as NSString).appendingPathComponent(file)
      let dst = (targetDir as NSString).appendingPathComponent(file)
      if fm.fileExists(atPath: dst) {
        try fm.removeItem(atPath: dst)
      }
      try fm.copyItem(atPath: src, toPath: dst)
    }
  }

  // MARK: - Cursor/Windsurf Rules Generation

  private func generateCursorRules(from pluginRoot: String?) -> String {
    var rules = """
      ---
      description: AgentSim — AI-driven iOS simulator exploration
      globs: ["**/*.swift", "**/*.xcodeproj/**"]
      ---

      # AgentSim

      Use `agent-sim` for all iOS Simulator interaction — QA sweeps, BDD journaling, regression replay.

      ## Commands

      | Command | Purpose |
      |---------|---------|
      | `agent-sim init` | Initialize AgentSim in this project |
      | `agent-sim status` | Check simulator and accessibility health |
      | `agent-sim explore --pretty` | Rich screen analysis |
      | `agent-sim next --journal <path>` | Get next typed instruction for sweep |
      | `agent-sim tap --label "element"` | Tap an element |
      | `agent-sim fingerprint --hash-only` | Get screen identity hash |
      | `agent-sim assert --contains "text"` | Verify element exists |
      | `agent-sim journal init --path <p>` | Create sweep journal |
      | `agent-sim journal log --path <p>` | Log an action |
      | `agent-sim journal summary --path <p>` | Print sweep stats |

      ## Path Resolution

      Journal path is resolved from config:
      1. Walk up from CWD looking for `.agent-sim/config.json`
      2. Fall back to `~/.config/agent-sim/config.json`
      3. Fall back to `build/agent-sim/`

      Use `agent-sim config journals` to get the resolved path.
      """

    // Append command content if available
    if let pluginRoot {
      let commandsDir = (pluginRoot as NSString).appendingPathComponent("commands")
      let fm = FileManager.default
      if let files = try? fm.contentsOfDirectory(atPath: commandsDir) {
        for file in files.sorted() where file.hasSuffix(".md") {
          let path = (commandsDir as NSString).appendingPathComponent(file)
          if let content = try? String(contentsOfFile: path, encoding: .utf8) {
            let name = (file as NSString).deletingPathExtension
            rules += "\n\n## /agentsim:\(name)\n\n\(content)"
          }
        }
      }
    }

    return rules
  }
}

// MARK: - Errors

enum InitError: Error, LocalizedError {
  case invalidScope(String)

  var errorDescription: String? {
    switch self {
    case .invalidScope(let scope):
      "Invalid scope '\(scope)'. Use 'project' or 'user'."
    }
  }
}
