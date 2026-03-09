import ArgumentParser

public struct AgentSim: AsyncParsableCommand {
  public init() {}

  public static let configuration = CommandConfiguration(
    commandName: "agent-sim",
    abstract: "AI-driven iOS Simulator exploration and acceptance test generation.",
    version: "0.1.8",
    subcommands: [
      SimGroup.self,
      UIGroup.self,
      ConfigGroup.self,
      ProjectGroupCmd.self,
      Explore.self,
      Tap.self,
      SwipeCmd.self,
      TypeText.self,
      Screenshot.self,
      Launch.self,
      Stop.self,
      Update.self,
      Doctor.self,
    ]
  )
}
