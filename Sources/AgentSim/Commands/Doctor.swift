import ArgumentParser
import Foundation

/// Check AgentSim installation health.
struct Doctor: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "doctor",
    abstract: "Check AgentSim installation health and report issues."
  )

  func run() throws {
    var issues: [String] = []
    let fm = FileManager.default
    let version = AgentSim.configuration.version

    // Binary version
    print("AgentSim Doctor")
    print("───────────────")
    print("  Binary version: \(version)")

    // Asset root
    if let assetRoot = ProjectConfig.assetRoot() {
      print("  Asset root:     \(assetRoot)")

      // Count bundled assets
      let commandsDir = (assetRoot as NSString).appendingPathComponent("commands")
      let templatesDir = (assetRoot as NSString).appendingPathComponent("Templates")
      let referencesDir = (assetRoot as NSString).appendingPathComponent("references")

      let commandCount = countFiles(in: commandsDir, ext: "md")
      let templateCount = countFiles(in: templatesDir, ext: "md")
      let referenceCount = countFiles(in: referencesDir)

      print("  Bundled assets:")
      print("    Commands:   \(commandCount)")
      print("    Templates:  \(templateCount)")
      print("    References: \(referenceCount)")
    } else {
      print("  Asset root:     NOT FOUND")
      issues.append("Bundled assets not found. Reinstall agent-sim or run from source checkout.")
    }

    // Project manifest
    print("")
    if let (manifest, dir) = ManifestIO.findProjectManifest() {
      print("  Project manifest: \(dir)/manifest.json")
      print("    Installed version: \(manifest.version)")
      print("    Installed at:      \(manifest.installedAt)")
      print("    Tools:             \(manifest.tools.joined(separator: ", "))")

      // Staleness check
      if manifest.version != version {
        print("    Status:            STALE (binary is v\(version))")
        issues.append("Manifest version (\(manifest.version)) differs from binary (v\(version)). Run `agent-sim update`.")
      } else {
        print("    Status:            current")
      }

      // Per-command integrity
      if !manifest.commands.isEmpty {
        print("")
        print("  Command integrity:")

        // Find install dir
        let projectRoot = (dir as NSString).deletingLastPathComponent
        let installDir = commandInstallDir(projectRoot: projectRoot, tools: manifest.tools)

        for (filename, entry) in manifest.commands.sorted(by: { $0.key < $1.key }) {
          let installedPath = (installDir as NSString).appendingPathComponent(filename)

          if !fm.fileExists(atPath: installedPath) {
            print("    \(filename): MISSING")
            issues.append("\(filename) is in manifest but not on disk.")
            continue
          }

          let diskSHA = FileChecksum.sha256(atPath: installedPath) ?? ""
          if diskSHA == entry.sha256 {
            print("    \(filename): OK (\(entry.source.rawValue))")
          } else {
            print("    \(filename): MODIFIED (installed differs from manifest)")
          }
        }
      }
    } else {
      print("  Project manifest: not found")
      print("    Run `agent-sim init` to initialize.")
    }

    // Issues summary
    print("")
    if issues.isEmpty {
      print("No issues found.")
    } else {
      print("\(issues.count) issue\(issues.count == 1 ? "" : "s") found:")
      for (i, issue) in issues.enumerated() {
        print("  \(i + 1). \(issue)")
      }
    }
  }

  // MARK: - Private

  private func countFiles(in dir: String, ext: String? = nil) -> Int {
    guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return 0 }
    if let ext {
      return files.filter { $0.hasSuffix(".\(ext)") }.count
    }
    return files.count
  }

  private func commandInstallDir(projectRoot: String, tools: [String]) -> String {
    for tool in tools {
      switch tool {
      case "claude":
        return (projectRoot as NSString).appendingPathComponent(".claude/commands/agentsim")
      case "opencode":
        return (projectRoot as NSString).appendingPathComponent(".opencode/commands/agentsim")
      default:
        continue
      }
    }

    // Legacy fallback when manifest tools don't include a command-aware target.
    return (projectRoot as NSString).appendingPathComponent(".claude/commands/agentsim")
  }
}
