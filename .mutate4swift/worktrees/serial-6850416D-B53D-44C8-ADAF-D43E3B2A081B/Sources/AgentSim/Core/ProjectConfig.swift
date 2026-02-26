import Foundation

/// Resolves AgentSim configuration by walking up the directory tree.
///
/// Resolution chain:
/// 1. Walk up from CWD looking for `.agent-sim/config.json`
/// 2. Fall back to `~/.config/agent-sim/config.json`
/// 3. Fall back to defaults
enum ProjectConfig {

  struct Config: Codable {
    var scope: Scope
    var journals: String

    enum Scope: String, Codable {
      case project
      case user
    }
  }

  // MARK: - Resolution

  /// Resolve the active config by walking up from the current directory,
  /// then falling back to user-level config.
  static func resolve() -> Config {
    if let projectConfig = findProjectConfig() {
      return projectConfig
    }
    if let userConfig = loadUserConfig() {
      return userConfig
    }
    return defaults
  }

  /// The resolved journals directory as an absolute path.
  static func journalsDirectory() -> String {
    let config = resolve()
    let path = config.journals

    if path.hasPrefix("/") {
      return path
    }
    if path.hasPrefix("~") {
      return NSString(string: path).expandingTildeInPath
    }

    // Relative path — resolve from the config file's parent directory
    if let configDir = findAgentSimDirectory() {
      let base = (configDir as NSString).deletingLastPathComponent
      return (base as NSString).appendingPathComponent(path)
    }

    // User-scope relative path — resolve from home
    if let _ = loadUserConfig() {
      let home = NSHomeDirectory()
      return (home as NSString).appendingPathComponent(
        ".config/agent-sim/\(path)"
      )
    }

    // No config — use CWD-relative default
    let cwd = FileManager.default.currentDirectoryPath
    return (cwd as NSString).appendingPathComponent(path)
  }

  /// Default journal file path within the resolved journals directory.
  static func defaultJournalPath() -> String {
    (journalsDirectory() as NSString).appendingPathComponent("sweep-journal.md")
  }

  // MARK: - Config File Locations

  static let configFileName = "config.json"
  static let configDirName = ".agent-sim"
  static let deviceFileName = "device"

  static var userConfigPath: String {
    let home = NSHomeDirectory()
    return "\(home)/.config/agent-sim/\(configFileName)"
  }

  static var defaults: Config {
    Config(scope: .project, journals: ".agent-sim/journals")
  }

  // MARK: - Device Pinning

  /// Read the pinned device UDID from `.agent-sim/device`.
  static func pinnedDeviceUDID() -> String? {
    if let configDir = findAgentSimDirectory() {
      let path = (configDir as NSString).appendingPathComponent(deviceFileName)
      if let content = try? String(contentsOfFile: path, encoding: .utf8) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
      }
    }
    // User-level fallback
    let userDir = "\(NSHomeDirectory())/.config/agent-sim"
    let userPath = (userDir as NSString).appendingPathComponent(deviceFileName)
    if let content = try? String(contentsOfFile: userPath, encoding: .utf8) {
      let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { return trimmed }
    }
    return nil
  }

  /// Write the pinned device UDID to `.agent-sim/device`.
  /// Returns the path that was written.
  @discardableResult
  static func pinDevice(_ udid: String) throws -> String {
    let dir: String
    if let configDir = findAgentSimDirectory() {
      dir = configDir
    } else {
      // Create .agent-sim/ in CWD
      dir = (FileManager.default.currentDirectoryPath as NSString)
        .appendingPathComponent(configDirName)
      try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }
    let path = (dir as NSString).appendingPathComponent(deviceFileName)
    try udid.write(toFile: path, atomically: true, encoding: .utf8)
    return path
  }

  /// Remove the pinned device file. Returns true if a file was removed.
  @discardableResult
  static func unpinDevice() -> Bool {
    if let configDir = findAgentSimDirectory() {
      let path = (configDir as NSString).appendingPathComponent(deviceFileName)
      return (try? FileManager.default.removeItem(atPath: path)) != nil
    }
    return false
  }

  // MARK: - Plugin Root

  /// Find the AgentSim plugin root (where commands/ and Templates/ live).
  /// Resolves symlinks on the executable path so it works when invoked via
  /// `~/.local/bin/agent-sim` symlink, then walks up looking for
  /// `.claude-plugin/plugin.json`.
  static func pluginRoot() -> String? {
    // Resolve symlinks so this works when invoked via ~/.local/bin/agent-sim
    guard let execURL = Bundle.main.executableURL else { return nil }
    let resolved = execURL.resolvingSymlinksInPath()
    var dir = resolved.deletingLastPathComponent().path

    for _ in 0 ..< 10 {
      let candidate = (dir as NSString).appendingPathComponent(".claude-plugin/plugin.json")
      if FileManager.default.fileExists(atPath: candidate) {
        return dir
      }
      let parent = (dir as NSString).deletingLastPathComponent
      if parent == dir { break }
      dir = parent
    }

    return nil
  }

  // MARK: - Asset Root

  /// Find the directory containing bundled assets (`commands/`, `Templates/`, `references/`).
  ///
  /// Discovery chain:
  /// 1. **Dev checkout**: existing `pluginRoot()` — walks up looking for `.claude-plugin/plugin.json`
  /// 2. **curl install**: `commands/` next to the resolved executable (`~/.local/lib/agent-sim/`)
  /// 3. **Homebrew**: `../lib/agent-sim/commands/` relative to executable dir
  static func assetRoot() -> String? {
    // 1. Dev checkout
    if let root = pluginRoot() {
      let commands = (root as NSString).appendingPathComponent("commands")
      if FileManager.default.fileExists(atPath: commands) {
        return root
      }
    }

    // Resolve executable location
    guard let execURL = Bundle.main.executableURL else { return nil }
    let resolved = execURL.resolvingSymlinksInPath()
    let execDir = resolved.deletingLastPathComponent().path

    // 2. curl install: assets live next to the binary
    let curlCandidate = (execDir as NSString).appendingPathComponent("commands")
    if FileManager.default.fileExists(atPath: curlCandidate) {
      return execDir
    }

    // 3. Homebrew: binary in bin/, assets in ../lib/agent-sim/
    let brewCandidate = ((execDir as NSString).deletingLastPathComponent as NSString)
      .appendingPathComponent("lib/agent-sim")
    let brewCommands = (brewCandidate as NSString).appendingPathComponent("commands")
    if FileManager.default.fileExists(atPath: brewCommands) {
      return brewCandidate
    }

    return nil
  }

  /// Path to the bundled `commands/` directory, if available.
  static func commandsPath() -> String? {
    guard let root = assetRoot() else { return nil }
    return (root as NSString).appendingPathComponent("commands")
  }

  /// Path to the bundled `Templates/` directory, if available.
  static func templatesPath() -> String? {
    guard let root = assetRoot() else { return nil }
    return (root as NSString).appendingPathComponent("Templates")
  }

  // MARK: - Private

  /// Walk up from CWD looking for `.agent-sim/config.json`.
  private static func findProjectConfig() -> Config? {
    guard let configDir = findAgentSimDirectory() else { return nil }
    let configPath = (configDir as NSString).appendingPathComponent(configFileName)
    return load(from: configPath)
  }

  /// Find the `.agent-sim/` directory by walking up from CWD.
  /// Matches on the directory existing (may contain config.json, device, manifest.json, or any combination).
  static func findAgentSimDirectory() -> String? {
    let fm = FileManager.default
    var dir = fm.currentDirectoryPath
    var isDir: ObjCBool = false

    while true {
      let candidate = (dir as NSString).appendingPathComponent(configDirName)
      if fm.fileExists(atPath: candidate, isDirectory: &isDir), isDir.boolValue {
        return candidate
      }

      let parent = (dir as NSString).deletingLastPathComponent
      if parent == dir { break } // reached root
      dir = parent
    }

    return nil
  }

  private static func loadUserConfig() -> Config? {
    load(from: userConfigPath)
  }

  private static func load(from path: String) -> Config? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    return try? JSONDecoder().decode(Config.self, from: data)
  }

  // MARK: - Write

  static func write(_ config: Config, to path: String) throws {
    let dir = (path as NSString).deletingLastPathComponent
    try FileManager.default.createDirectory(
      atPath: dir, withIntermediateDirectories: true
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(config)
    try data.write(to: URL(fileURLWithPath: path))
  }
}
