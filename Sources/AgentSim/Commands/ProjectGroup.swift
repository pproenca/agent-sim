import ArgumentParser
import Foundation

struct ProjectGroupCmd: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "project",
    abstract: "Project discovery and settings.",
    subcommands: [ProjectContext.self]
  )
}

struct ProjectContext: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "context",
    abstract: "Discover workspace, schemes, simulators, and build configurations."
  )

  func run() async throws {
    let buildConfig = try? ProjectConfig.loadBuildConfig()
    let devices = (try? await SimulatorBridge.allDevices()) ?? []
    let output = ProjectContextOutput(
      workspace: buildConfig?.workspace,
      scheme: buildConfig?.scheme,
      simulator: buildConfig?.simulator,
      configuration: buildConfig?.configuration ?? "Debug",
      simulators: devices.map { SimInfo(name: $0.name, udid: $0.udid, state: $0.state) }
    )
    JSONOutput.print(output)
  }
}

private struct ProjectContextOutput: Encodable {
  let workspace: String?
  let scheme: String?
  let simulator: String?
  let configuration: String
  let simulators: [SimInfo]
}

private struct SimInfo: Encodable {
  let name: String
  let udid: String
  let state: String
}
