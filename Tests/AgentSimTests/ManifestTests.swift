import Testing
import Foundation
@testable import AgentSimLib

@Suite("Manifest — model and diff logic")
struct ManifestTests {

  // MARK: - Round-trip

  @Test("Manifest round-trips through Codable")
  func codableRoundTrip() throws {
    let manifest = Manifest(
      version: "0.3.0",
      installedAt: "2025-01-15T10:30:00Z",
      tools: ["claude", "cursor"],
      commands: [
        "new.md": Manifest.FileEntry(sha256: "abc123", source: .bundled),
        "apply.md": Manifest.FileEntry(sha256: "def456", source: .stub),
      ]
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(manifest)
    let decoded = try JSONDecoder().decode(Manifest.self, from: data)

    #expect(decoded.version == "0.3.0")
    #expect(decoded.installedAt == "2025-01-15T10:30:00Z")
    #expect(decoded.tools == ["claude", "cursor"])
    #expect(decoded.commands.count == 2)
    #expect(decoded.commands["new.md"]?.sha256 == "abc123")
    #expect(decoded.commands["new.md"]?.source == .bundled)
    #expect(decoded.commands["apply.md"]?.source == .stub)
  }

  @Test("FileEntry source encodes as string")
  func sourceEncoding() throws {
    let bundled = Manifest.FileEntry(sha256: "aaa", source: .bundled)
    let stub = Manifest.FileEntry(sha256: "bbb", source: .stub)

    let encoder = JSONEncoder()
    let bundledJSON = String(data: try encoder.encode(bundled), encoding: .utf8)!
    let stubJSON = String(data: try encoder.encode(stub), encoding: .utf8)!

    #expect(bundledJSON.contains("\"bundled\""))
    #expect(stubJSON.contains("\"stub\""))
  }

  // MARK: - FileChecksum

  @Test("SHA-256 produces consistent hex digest")
  func sha256Consistency() {
    let data = Data("hello world".utf8)
    let hash1 = FileChecksum.sha256(data)
    let hash2 = FileChecksum.sha256(data)

    #expect(hash1 == hash2)
    #expect(hash1.count == 64) // SHA-256 = 32 bytes = 64 hex chars
  }

  @Test("SHA-256 of known input matches expected value")
  func sha256KnownValue() {
    let data = Data("hello".utf8)
    let hash = FileChecksum.sha256(data)
    // SHA-256("hello") = 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
    #expect(hash == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
  }

  @Test("SHA-256 atPath returns nil for missing file")
  func sha256MissingFile() {
    let result = FileChecksum.sha256(atPath: "/nonexistent/path/file.txt")
    #expect(result == nil)
  }

  @Test("SHA-256 atPath reads and hashes file content")
  func sha256AtPath() throws {
    let tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent("agentsim-checksum-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

    let filePath = tmp.appendingPathComponent("test.txt").path
    try "hello".write(toFile: filePath, atomically: true, encoding: .utf8)

    let hash = FileChecksum.sha256(atPath: filePath)
    let expected = FileChecksum.sha256(Data("hello".utf8))
    #expect(hash == expected)

    try FileManager.default.removeItem(atPath: tmp.path)
  }

  // MARK: - Diff

  @Test("Diff detects added files")
  func diffAdded() throws {
    let (bundledDir, installDir) = try makeTempDirs()

    // Bundled has a file, manifest does not
    try "content".write(
      toFile: (bundledDir as NSString).appendingPathComponent("new.md"),
      atomically: true, encoding: .utf8
    )

    let manifest = Manifest(
      version: "0.1.0", installedAt: "", tools: [], commands: [:]
    )

    let diffs = ManifestDiff.diff(
      bundledDir: bundledDir, manifest: manifest, installDir: installDir
    )

    #expect(diffs.count == 1)
    #expect(diffs[0].filename == "new.md")
    #expect(diffs[0].kind == .added)

    try cleanupDirs(bundledDir, installDir)
  }

  @Test("Diff detects unchanged files")
  func diffUnchanged() throws {
    let (bundledDir, installDir) = try makeTempDirs()
    let content = "same content"
    let sha = FileChecksum.sha256(Data(content.utf8))

    try content.write(
      toFile: (bundledDir as NSString).appendingPathComponent("cmd.md"),
      atomically: true, encoding: .utf8
    )
    try content.write(
      toFile: (installDir as NSString).appendingPathComponent("cmd.md"),
      atomically: true, encoding: .utf8
    )

    let manifest = Manifest(
      version: "0.1.0", installedAt: "", tools: [],
      commands: ["cmd.md": .init(sha256: sha, source: .bundled)]
    )

    let diffs = ManifestDiff.diff(
      bundledDir: bundledDir, manifest: manifest, installDir: installDir
    )

    #expect(diffs.count == 1)
    #expect(diffs[0].kind == .unchanged)
    #expect(diffs[0].userModified == false)

    try cleanupDirs(bundledDir, installDir)
  }

  @Test("Diff detects updated files")
  func diffUpdated() throws {
    let (bundledDir, installDir) = try makeTempDirs()
    let oldContent = "old content"
    let oldSHA = FileChecksum.sha256(Data(oldContent.utf8))

    try "new content".write(
      toFile: (bundledDir as NSString).appendingPathComponent("cmd.md"),
      atomically: true, encoding: .utf8
    )
    try oldContent.write(
      toFile: (installDir as NSString).appendingPathComponent("cmd.md"),
      atomically: true, encoding: .utf8
    )

    let manifest = Manifest(
      version: "0.1.0", installedAt: "", tools: [],
      commands: ["cmd.md": .init(sha256: oldSHA, source: .bundled)]
    )

    let diffs = ManifestDiff.diff(
      bundledDir: bundledDir, manifest: manifest, installDir: installDir
    )

    #expect(diffs.count == 1)
    #expect(diffs[0].kind == .updated)
    #expect(diffs[0].userModified == false) // installed matches manifest

    try cleanupDirs(bundledDir, installDir)
  }

  @Test("Diff detects removed files")
  func diffRemoved() throws {
    let (bundledDir, installDir) = try makeTempDirs()
    let content = "old command"
    let sha = FileChecksum.sha256(Data(content.utf8))

    // File in manifest and on disk, but not in bundled
    try content.write(
      toFile: (installDir as NSString).appendingPathComponent("old.md"),
      atomically: true, encoding: .utf8
    )

    let manifest = Manifest(
      version: "0.1.0", installedAt: "", tools: [],
      commands: ["old.md": .init(sha256: sha, source: .bundled)]
    )

    let diffs = ManifestDiff.diff(
      bundledDir: bundledDir, manifest: manifest, installDir: installDir
    )

    #expect(diffs.count == 1)
    #expect(diffs[0].kind == .removed)
    #expect(diffs[0].userModified == false)

    try cleanupDirs(bundledDir, installDir)
  }

  @Test("Diff detects user modification")
  func diffUserModified() throws {
    let (bundledDir, installDir) = try makeTempDirs()
    let originalContent = "original"
    let originalSHA = FileChecksum.sha256(Data(originalContent.utf8))

    // Bundled has new content
    try "updated bundled".write(
      toFile: (bundledDir as NSString).appendingPathComponent("cmd.md"),
      atomically: true, encoding: .utf8
    )
    // User modified the installed file
    try "user edited".write(
      toFile: (installDir as NSString).appendingPathComponent("cmd.md"),
      atomically: true, encoding: .utf8
    )

    let manifest = Manifest(
      version: "0.1.0", installedAt: "", tools: [],
      commands: ["cmd.md": .init(sha256: originalSHA, source: .bundled)]
    )

    let diffs = ManifestDiff.diff(
      bundledDir: bundledDir, manifest: manifest, installDir: installDir
    )

    #expect(diffs.count == 1)
    #expect(diffs[0].kind == .updated)
    #expect(diffs[0].userModified == true)

    try cleanupDirs(bundledDir, installDir)
  }

  @Test("Diff handles mixed scenario: added + unchanged + removed")
  func diffMixed() throws {
    let (bundledDir, installDir) = try makeTempDirs()

    let keepContent = "keep"
    let keepSHA = FileChecksum.sha256(Data(keepContent.utf8))

    // Bundled: has keep.md and new.md
    try keepContent.write(
      toFile: (bundledDir as NSString).appendingPathComponent("keep.md"),
      atomically: true, encoding: .utf8
    )
    try "brand new".write(
      toFile: (bundledDir as NSString).appendingPathComponent("new.md"),
      atomically: true, encoding: .utf8
    )

    // Installed: has keep.md and old.md
    try keepContent.write(
      toFile: (installDir as NSString).appendingPathComponent("keep.md"),
      atomically: true, encoding: .utf8
    )
    try "old command".write(
      toFile: (installDir as NSString).appendingPathComponent("old.md"),
      atomically: true, encoding: .utf8
    )

    let manifest = Manifest(
      version: "0.1.0", installedAt: "", tools: [],
      commands: [
        "keep.md": .init(sha256: keepSHA, source: .bundled),
        "old.md": .init(sha256: "whatever", source: .bundled),
      ]
    )

    let diffs = ManifestDiff.diff(
      bundledDir: bundledDir, manifest: manifest, installDir: installDir
    )

    #expect(diffs.count == 3)

    let byName = Dictionary(uniqueKeysWithValues: diffs.map { ($0.filename, $0) })
    #expect(byName["keep.md"]?.kind == .unchanged)
    #expect(byName["new.md"]?.kind == .added)
    #expect(byName["old.md"]?.kind == .removed)

    try cleanupDirs(bundledDir, installDir)
  }

  // MARK: - ManifestIO

  @Test("ManifestIO write and load round-trip")
  func ioRoundTrip() throws {
    let tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent("agentsim-manifest-\(UUID().uuidString)")

    let manifest = Manifest(
      version: "1.0.0",
      installedAt: "2025-06-01T12:00:00Z",
      tools: ["claude"],
      commands: ["new.md": .init(sha256: "abc", source: .bundled)]
    )

    try ManifestIO.write(manifest, toDir: tmp.path)

    let loaded = ManifestIO.load(from: tmp.path)
    #expect(loaded != nil)
    #expect(loaded?.version == "1.0.0")
    #expect(loaded?.commands["new.md"]?.sha256 == "abc")

    try FileManager.default.removeItem(at: tmp)
  }

  // MARK: - Helpers

  private func makeTempDirs() throws -> (bundled: String, install: String) {
    let base = FileManager.default.temporaryDirectory
      .appendingPathComponent("agentsim-diff-\(UUID().uuidString)")
    let bundled = base.appendingPathComponent("bundled")
    let install = base.appendingPathComponent("install")
    try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: install, withIntermediateDirectories: true)
    return (bundled.path, install.path)
  }

  private func cleanupDirs(_ dirs: String...) throws {
    for dir in dirs {
      let parent = (dir as NSString).deletingLastPathComponent
      try? FileManager.default.removeItem(atPath: parent)
    }
  }
}
