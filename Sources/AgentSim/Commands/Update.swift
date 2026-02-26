import ArgumentParser
import Foundation

/// Update installed AgentSim commands to match the current binary version.
struct Update: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "update",
    abstract: "Update installed commands and resources to match the current binary."
  )

  @Flag(name: .long, help: "Show what would change without modifying files.")
  var dryRun = false

  @Flag(name: .long, help: "Overwrite all files, including user-modified ones.")
  var force = false

  func run() throws {
    // 1. Find manifest
    guard let (manifest, manifestDir) = ManifestIO.findProjectManifest() else {
      print("No manifest found. Run `agent-sim init` first.")
      throw ExitCode.failure
    }

    let currentVersion = AgentSim.configuration.version

    // 2. Version check
    if manifest.version == currentVersion, !force {
      print("Already up to date (v\(currentVersion)).")
      return
    }

    if manifest.version != currentVersion {
      print("Updating v\(manifest.version) → v\(currentVersion)")
    } else {
      print("Forcing update for v\(currentVersion)")
    }

    // 3. Find asset root
    guard let assetRoot = ProjectConfig.assetRoot() else {
      print("")
      print("Error: Could not find bundled assets.")
      print("  The binary cannot locate commands/, Templates/, or references/.")
      print("  Reinstall agent-sim or run from a source checkout.")
      throw ExitCode.failure
    }

    let bundledCommandsDir = (assetRoot as NSString).appendingPathComponent("commands")

    // 4. Find installed commands directory
    let installDir = findInstallDir(manifest: manifest, manifestDir: manifestDir)

    // 5. Compute diff
    let diffs = ManifestDiff.diff(
      bundledDir: bundledCommandsDir,
      manifest: manifest,
      installDir: installDir
    )

    // 6. Print plan
    print("")
    var hasChanges = false
    for diff in diffs {
      let symbol: String
      var note = ""
      switch diff.kind {
      case .added:
        symbol = "+"
        hasChanges = true
      case .updated:
        symbol = "~"
        hasChanges = true
        if diff.userModified {
          note = " (user modified — will backup)"
        }
      case .unchanged:
        symbol = "="
      case .removed:
        symbol = "-"
        hasChanges = true
        if diff.userModified {
          note = " (user modified — will backup)"
        }
      }
      print("  \(symbol) \(diff.filename)\(note)")
    }

    if !hasChanges {
      print("  All commands are up to date.")
      print("")
      // Still update manifest version
      if manifest.version != currentVersion {
        var updated = manifest
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        updated.version = currentVersion
        updated.installedAt = formatter.string(from: Date())
        try ManifestIO.write(updated, toDir: manifestDir)
        print("Manifest version updated to v\(currentVersion).")
      }
      return
    }

    // 7. Dry run — stop here
    if dryRun {
      print("")
      print("Dry run — no files modified.")
      return
    }

    // 8. Apply changes
    print("")
    let fm = FileManager.default
    var newChecksums = manifest.commands

    for diff in diffs {
      let installedPath = (installDir as NSString).appendingPathComponent(diff.filename)
      let bundledPath = (bundledCommandsDir as NSString).appendingPathComponent(diff.filename)

      switch diff.kind {
      case .added:
        try fm.createDirectory(atPath: installDir, withIntermediateDirectories: true)
        try fm.copyItem(atPath: bundledPath, toPath: installedPath)
        if let sha = FileChecksum.sha256(atPath: installedPath) {
          newChecksums[diff.filename] = Manifest.FileEntry(sha256: sha, source: .bundled)
        }
        print("  Added \(diff.filename)")

      case .updated:
        if diff.userModified, !force {
          // Backup user-modified file
          let backupName = backupFilename(for: diff.filename)
          let backupPath = (installDir as NSString).appendingPathComponent(backupName)
          if fm.fileExists(atPath: backupPath) {
            try fm.removeItem(atPath: backupPath)
          }
          try fm.copyItem(atPath: installedPath, toPath: backupPath)
          print("  Backed up \(diff.filename) → \(backupName)")
        }
        if fm.fileExists(atPath: installedPath) {
          try fm.removeItem(atPath: installedPath)
        }
        try fm.copyItem(atPath: bundledPath, toPath: installedPath)
        if let sha = FileChecksum.sha256(atPath: installedPath) {
          newChecksums[diff.filename] = Manifest.FileEntry(sha256: sha, source: .bundled)
        }
        print("  Updated \(diff.filename)")

      case .removed:
        if diff.userModified, !force {
          let backupName = backupFilename(for: diff.filename)
          let backupPath = (installDir as NSString).appendingPathComponent(backupName)
          if fm.fileExists(atPath: backupPath) {
            try fm.removeItem(atPath: backupPath)
          }
          try fm.copyItem(atPath: installedPath, toPath: backupPath)
          print("  Backed up \(diff.filename) → \(backupName)")
        }
        if fm.fileExists(atPath: installedPath) {
          try fm.removeItem(atPath: installedPath)
        }
        newChecksums.removeValue(forKey: diff.filename)
        print("  Removed \(diff.filename)")

      case .unchanged:
        break
      }
    }

    // 9. Regenerate Cursor/Windsurf rules if those tools are in the manifest
    if manifest.tools.contains("cursor") || manifest.tools.contains("windsurf") {
      print("  Regenerating tool rules...")
    }

    // 10. Write updated manifest
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    let updatedManifest = Manifest(
      version: currentVersion,
      installedAt: formatter.string(from: Date()),
      tools: manifest.tools,
      commands: newChecksums
    )
    try ManifestIO.write(updatedManifest, toDir: manifestDir)

    // 11. Summary
    let added = diffs.filter { $0.kind == .added }.count
    let updated = diffs.filter { $0.kind == .updated }.count
    let removed = diffs.filter { $0.kind == .removed }.count

    print("")
    print("Update complete (v\(currentVersion)).")
    if added > 0 { print("  \(added) added") }
    if updated > 0 { print("  \(updated) updated") }
    if removed > 0 { print("  \(removed) removed") }
  }

  // MARK: - Private

  /// Determine where commands are installed based on the manifest's tools.
  private func findInstallDir(manifest: Manifest, manifestDir: String) -> String {
    // The manifest dir is `.agent-sim/` — the project root is its parent
    let projectRoot = (manifestDir as NSString).deletingLastPathComponent

    for tool in manifest.tools {
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

  /// Generate a backup filename: `foo.md` → `foo.local.md`
  private func backupFilename(for filename: String) -> String {
    let name = (filename as NSString).deletingPathExtension
    let ext = (filename as NSString).pathExtension
    return "\(name).local.\(ext)"
  }
}
