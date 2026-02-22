// Inlined from AXe (cameroncooke/AXe) — MIT License
// Original: Copyright (c) Meta Platforms, Inc. and affiliates.
@preconcurrency import FBControlCore
import Foundation

enum FBFutureError: Error {
  case continuationFulfilledWithoutValues
  case unexpectedType(expected: String, actual: String)
}

enum FutureBridge {

  static func value<T: AnyObject>(_ future: FBFuture<T>) async throws -> T {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        future.onQueue(BridgeQueues.futureSerialFullfillmentQueue, notifyOfCompletion: { resolved in
          if let error = resolved.error {
            continuation.resume(throwing: error)
          } else if let value = resolved.result {
            guard let typed = value as? T else {
              continuation.resume(throwing: FBFutureError.unexpectedType(
                expected: "\(T.self)", actual: "\(type(of: value))"))
              return
            }
            continuation.resume(returning: typed)
          } else {
            continuation.resume(throwing: FBFutureError.continuationFulfilledWithoutValues)
          }
        })
      }
    } onCancel: {
      future.cancel()
    }
  }

  static func value(_ future: FBFuture<NSNull>) async throws {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        future.onQueue(BridgeQueues.futureSerialFullfillmentQueue, notifyOfCompletion: { resolved in
          if let error = resolved.error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume(returning: ())
          }
        })
      }
    } onCancel: {
      future.cancel()
    }
  }
}
