import Foundation

/// Tracks installed command files, their checksums, and the version that wrote them.
/// Stored at `.agent-sim/manifest.json`.
struct Manifest: Codable {
  var version: String
  var installedAt: String
  var tools: [String]
  var commands: [String: FileEntry]

  struct FileEntry: Codable {
    var sha256: String
    var source: Source

    enum Source: String, Codable {
      case bundled
      case stub
    }
  }

  static let fileName = "manifest.json"
}

/// IO operations for reading and writing manifests.
enum ManifestIO {

  /// Load a manifest from a directory (reads `manifest.json` inside it).
  static func load(from directory: String) -> Manifest? {
    let path = (directory as NSString).appendingPathComponent(Manifest.fileName)
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    return try? JSONDecoder().decode(Manifest.self, from: data)
  }

  /// Write a manifest to a directory (writes `manifest.json` inside it).
  static func write(_ manifest: Manifest, toDir directory: String) throws {
    try FileManager.default.createDirectory(
      atPath: directory, withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(manifest)
    let path = (directory as NSString).appendingPathComponent(Manifest.fileName)
    try data.write(to: URL(fileURLWithPath: path))
  }

  /// Find the project's `.agent-sim/` directory and load the manifest from it.
  static func findProjectManifest() -> (manifest: Manifest, directory: String)? {
    guard let dir = ProjectConfig.findAgentSimDirectory() else { return nil }
    guard let manifest = load(from: dir) else { return nil }
    return (manifest, dir)
  }
}

// MARK: - Diff

/// Describes how a single command file differs between the bundled source and the installed copy.
enum FileDiffKind {
  case added        // in bundled, not in manifest
  case updated      // in both, bundled SHA differs from manifest SHA
  case unchanged    // in both, SHAs match
  case removed      // in manifest, not in bundled
}

struct FileDiff {
  let filename: String
  let kind: FileDiffKind
  let userModified: Bool  // installed file on disk differs from manifest SHA
}

enum ManifestDiff {

  /// Compute the diff between bundled assets and the current manifest.
  ///
  /// - Parameters:
  ///   - bundledDir: path to the bundled `commands/` directory
  ///   - manifest: the current manifest
  ///   - installDir: path where commands are installed on disk
  static func diff(
    bundledDir: String,
    manifest: Manifest,
    installDir: String
  ) -> [FileDiff] {
    let fm = FileManager.default
    var results: [FileDiff] = []

    // Bundled files
    let bundledFiles = (try? fm.contentsOfDirectory(atPath: bundledDir))?
      .filter { $0.hasSuffix(".md") }
      .sorted() ?? []

    let bundledSet = Set(bundledFiles)
    let manifestSet = Set(manifest.commands.keys)

    // Added: in bundled, not in manifest
    for file in bundledFiles where !manifestSet.contains(file) {
      results.append(FileDiff(filename: file, kind: .added, userModified: false))
    }

    // Updated or Unchanged: in both
    for file in bundledFiles where manifestSet.contains(file) {
      let bundledPath = (bundledDir as NSString).appendingPathComponent(file)
      let bundledSHA = FileChecksum.sha256(atPath: bundledPath) ?? ""
      let manifestSHA = manifest.commands[file]?.sha256 ?? ""

      let kind: FileDiffKind = (bundledSHA == manifestSHA) ? .unchanged : .updated

      // Check user modification: installed file vs manifest SHA
      let installedPath = (installDir as NSString).appendingPathComponent(file)
      let installedSHA = FileChecksum.sha256(atPath: installedPath) ?? ""
      let userModified = installedSHA != manifestSHA

      results.append(FileDiff(filename: file, kind: kind, userModified: userModified))
    }

    // Removed: in manifest, not in bundled
    for file in manifest.commands.keys.sorted() where !bundledSet.contains(file) {
      let installedPath = (installDir as NSString).appendingPathComponent(file)
      let installedSHA = FileChecksum.sha256(atPath: installedPath) ?? ""
      let manifestSHA = manifest.commands[file]?.sha256 ?? ""
      let userModified = installedSHA != manifestSHA

      results.append(FileDiff(filename: file, kind: .removed, userModified: userModified))
    }

    return results.sorted { $0.filename < $1.filename }
  }
}
