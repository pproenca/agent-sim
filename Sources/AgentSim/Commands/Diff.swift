import ArgumentParser
import Foundation

/// Shows what changed between the last `explore` snapshot and the current screen.
struct Diff: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Show what changed on screen since the last explore."
  )

  func run() async throws {
    // Load previous snapshot
    let previous: RefSnapshot
    do {
      previous = try RefStore.load()
    } catch {
      print("No previous explore to diff against. Run 'agent-sim explore -i' first.")
      return
    }

    // Read current screen
    let device = try await SimulatorBridge.resolveDevice()
    let simNode = try await AXTreeReader.readDeviceTree(simulatorUDID: device.udid)
    let analysis = ScreenAnalyzer.analyze(simNode)
    let currentRefs = RefStore.buildRefs(from: analysis)

    // Quick check: same screen?
    if previous.fingerprint == analysis.fingerprint {
      print("[same] \(analysis.screenName) — no changes detected")
      return
    }

    // Screen changed
    print("Screen: \(previous.screenName) -> \(analysis.screenName)")
    print("")

    // Build lookup by name+role for comparison
    let prevByKey = Dictionary(
      previous.refs.map { ("\($0.role)|\($0.name)", $0) },
      uniquingKeysWith: { first, _ in first }
    )
    let currByKey = Dictionary(
      currentRefs.map { ("\($0.role)|\($0.name)", $0) },
      uniquingKeysWith: { first, _ in first }
    )

    let prevKeys = Set(prevByKey.keys)
    let currKeys = Set(currByKey.keys)

    let added = currKeys.subtracting(prevKeys)
    let removed = prevKeys.subtracting(currKeys)
    let shared = prevKeys.intersection(currKeys)

    if !added.isEmpty {
      print("Added:")
      for key in added.sorted() {
        if let ref = currByKey[key] {
          print("  @\(ref.ref) [\(ref.shortRole)] \"\(ref.name)\"")
        }
      }
      print("")
    }

    if !removed.isEmpty {
      print("Removed:")
      for key in removed.sorted() {
        if let ref = prevByKey[key] {
          print("  [\(ref.shortRole)] \"\(ref.name)\"")
        }
      }
      print("")
    }

    // Check for moved elements
    var moved: [(RefEntry, RefEntry)] = []
    for key in shared {
      if let prev = prevByKey[key], let curr = currByKey[key] {
        if prev.tapX != curr.tapX || prev.tapY != curr.tapY {
          moved.append((prev, curr))
        }
      }
    }

    if !moved.isEmpty {
      print("Moved:")
      for (prev, curr) in moved {
        print("  @\(curr.ref) [\(curr.shortRole)] \"\(curr.name)\" (\(prev.tapX),\(prev.tapY) -> \(curr.tapX),\(curr.tapY))")
      }
      print("")
    }

    if added.isEmpty && removed.isEmpty && moved.isEmpty {
      print("Elements are the same but fingerprint changed (content or layout shift).")
    }
  }
}
