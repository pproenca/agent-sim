// Inlined from AXe (cameroncooke/AXe) — MIT License
// Original: Copyright (c) Meta Platforms, Inc. and affiliates.
import Foundation

enum BridgeQueues {
  static let futureSerialFullfillmentQueue = DispatchQueue(
    label: "com.agent-sim.fbfuture.fulfillment"
  )
}
