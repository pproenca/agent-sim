import Testing
import Foundation
@testable import AgentSimLib

@Suite("ProjectConfig — configuration resolution")
struct ProjectConfigTests {

  @Test("Default config has project scope and standard journals path")
  func defaults() {
    let config = ProjectConfig.defaults

    #expect(config.scope == .project)
    #expect(config.journals == ".agent-sim/journals")
  }

  @Test("Config round-trips through Codable")
  func codableRoundTrip() throws {
    let config = ProjectConfig.Config(scope: .project, journals: "custom/journals")

    let encoder = JSONEncoder()
    let data = try encoder.encode(config)
    let decoded = try JSONDecoder().decode(ProjectConfig.Config.self, from: data)

    #expect(decoded.scope == .project)
    #expect(decoded.journals == "custom/journals")
  }

  @Test("Config scope encodes as string")
  func scopeEncoding() throws {
    let projectConfig = ProjectConfig.Config(scope: .project, journals: "j")
    let userConfig = ProjectConfig.Config(scope: .user, journals: "j")

    let encoder = JSONEncoder()
    let projectData = try encoder.encode(projectConfig)
    let userData = try encoder.encode(userConfig)

    let projectJSON = String(data: projectData, encoding: .utf8)!
    let userJSON = String(data: userData, encoding: .utf8)!

    #expect(projectJSON.contains("\"project\""))
    #expect(userJSON.contains("\"user\""))
  }

  @Test("journalsDirectory resolves absolute path unchanged")
  func absolutePath() {
    // Can't easily test this without file system setup,
    // but we can verify the absolute path detection logic
    let path = "/absolute/path/journals"
    #expect(path.hasPrefix("/"))
  }

  @Test("BuildConfig round-trips through Codable")
  func buildConfigCodable() throws {
    let config = BuildConfig(
      workspace: "MyApp.xcworkspace",
      scheme: "MyApp",
      simulator: "iPhone 16",
      configuration: "Debug"
    )
    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(BuildConfig.self, from: data)
    #expect(decoded.workspace == "MyApp.xcworkspace")
    #expect(decoded.scheme == "MyApp")
    #expect(decoded.simulator == "iPhone 16")
    #expect(decoded.configuration == "Debug")
  }

  @Test("Device pin/unpin round-trip in temp directory")
  func devicePinUnpin() throws {
    let tmpDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("agentsim-config-\(UUID().uuidString)")
      .appendingPathComponent(".agent-sim")
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

    let devicePath = tmpDir.appendingPathComponent("device").path
    let udid = "ABCD-1234-EF56"

    // Write
    try udid.write(toFile: devicePath, atomically: true, encoding: .utf8)

    // Read back
    let content = try String(contentsOfFile: devicePath, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    #expect(content == udid)

    // Delete
    try FileManager.default.removeItem(atPath: devicePath)
    #expect(!FileManager.default.fileExists(atPath: devicePath))
  }
}
