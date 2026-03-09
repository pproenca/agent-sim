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
      Diff.self,
      Describe.self,
      Tap.self,
      SwipeCmd.self,
      TypeText.self,
      Screenshot.self,
      FingerprintCmd.self,
      Journal.self,
      Launch.self,
      Terminate.self,
      Network.self,
      Status.self,
      Update.self,
      Doctor.self,
    ]
  )
}
