import ArgumentParser

public struct AgentSim: AsyncParsableCommand {
  public init() {}

  public static let configuration = CommandConfiguration(
    commandName: "agent-sim",
    abstract: "AI-driven iOS Simulator exploration and acceptance test generation.",
    version: "0.1.4",
    subcommands: [
      Init.self,
      Boot.self,
      AppInstall.self,
      Apps.self,
      Wait.self,
      Use.self,
      ConfigCmd.self,
      Next.self,
      Explore.self,
      Describe.self,
      Tap.self,
      SwipeCmd.self,
      TypeText.self,
      Screenshot.self,
      FingerprintCmd.self,
      Assert.self,
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
