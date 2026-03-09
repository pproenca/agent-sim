import ArgumentParser

public struct AgentSim: AsyncParsableCommand {
  public init() {}

  public static let configuration = CommandConfiguration(
    commandName: "agent-sim",
    abstract: "AI-driven iOS Simulator exploration and acceptance test generation.",
    version: "0.1.8",
    subcommands: [
      Init.self,
      SimGroup.self,
      UIGroup.self,
      Use.self,
      ConfigGroup.self,
      ProjectGroupCmd.self,
      Next.self,
      Explore.self,
      Tap.self,
      SwipeCmd.self,
      TypeText.self,
      Screenshot.self,
      Journal.self,
      Launch.self,
      Stop.self,
      Network.self,
      Status.self,
      Update.self,
      Doctor.self,
    ]
  )
}
