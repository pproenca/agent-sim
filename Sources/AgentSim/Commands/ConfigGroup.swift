import ArgumentParser
import Foundation

struct ConfigGroup: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "config",
    abstract: "Save and show project settings.",
    subcommands: [ConfigSet.self, ConfigShow.self]
  )
}

struct ConfigSet: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "set",
    abstract: "Save workspace, scheme, simulator defaults."
  )

  @Option(name: .shortAndLong, help: "Path to .xcworkspace or .xcodeproj")
  var workspace: String?

  @Option(name: .shortAndLong, help: "Scheme name")
  var scheme: String?

  @Option(name: [.customShort("S"), .long], help: "Simulator name or UDID")
  var simulator: String?

  @Option(name: [.customShort("C"), .long], help: "Build configuration (Debug/Release)")
  var buildConfiguration: String?

  func run() throws {
    var config = (try? ProjectConfig.loadBuildConfig()) ?? BuildConfig()
    if let workspace { config.workspace = workspace }
    if let scheme { config.scheme = scheme }
    if let simulator { config.simulator = simulator }
    if let buildConfiguration { config.configuration = buildConfiguration }
    try ProjectConfig.saveBuildConfig(config)
    JSONOutput.print(config)
  }
}

struct ConfigShow: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "show",
    abstract: "Show current configuration."
  )

  func run() throws {
    let config = ProjectConfig.resolve()
    let buildConfig = try? ProjectConfig.loadBuildConfig()
    let output = ConfigShowOutput(
      scope: config.scope.rawValue,
      journals: ProjectConfig.journalsDirectory(),
      workspace: buildConfig?.workspace,
      scheme: buildConfig?.scheme,
      simulator: buildConfig?.simulator,
      configuration: buildConfig?.configuration
    )
    JSONOutput.print(output)
  }
}

private struct ConfigShowOutput: Encodable {
  let scope: String
  let journals: String
  let workspace: String?
  let scheme: String?
  let simulator: String?
  let configuration: String?
}
