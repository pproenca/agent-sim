import ArgumentParser
import Foundation

/// Query resolved AgentSim configuration.
struct ConfigCmd: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "config",
    abstract: "Print resolved configuration values."
  )

  @Argument(help: "Config key to query: 'journals', 'scope', 'path', 'root', or 'all'.")
  var key: String = "all"

  func run() throws {
    let config = ProjectConfig.resolve()

    switch key {
    case "journals":
      print(ProjectConfig.journalsDirectory())

    case "scope":
      print(config.scope.rawValue)

    case "path":
      // Print the path to the config file that was resolved
      if let dir = findConfigPath() {
        print(dir)
      } else {
        print("No config found. Run `agent-sim init` to set up.")
      }

    case "root":
      if let root = ProjectConfig.assetRoot() {
        print(root)
      } else if let root = ProjectConfig.pluginRoot() {
        print(root)
      } else {
        print("Could not resolve AgentSim root. Is the binary installed correctly?")
      }

    case "all":
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(config)
      print(String(data: data, encoding: .utf8) ?? "{}")
      print("")
      print("Resolved journals directory: \(ProjectConfig.journalsDirectory())")
      if let root = ProjectConfig.assetRoot() {
        print("Asset root: \(root)")
      } else if let root = ProjectConfig.pluginRoot() {
        print("Plugin root: \(root)")
      }

    default:
      print("Unknown key: \(key)")
      print("Available keys: journals, scope, path, root, all")
    }
  }

  private func findConfigPath() -> String? {
    // Check project-level
    let fm = FileManager.default
    var dir = fm.currentDirectoryPath

    while true {
      let candidate = (dir as NSString)
        .appendingPathComponent(ProjectConfig.configDirName)
      let configFile = (candidate as NSString)
        .appendingPathComponent(ProjectConfig.configFileName)
      if fm.fileExists(atPath: configFile) {
        return configFile
      }
      let parent = (dir as NSString).deletingLastPathComponent
      if parent == dir { break }
      dir = parent
    }

    // Check user-level
    if fm.fileExists(atPath: ProjectConfig.userConfigPath) {
      return ProjectConfig.userConfigPath
    }

    return nil
  }
}
