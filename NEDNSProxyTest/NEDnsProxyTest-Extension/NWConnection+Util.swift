//
//  NWConnection+Util.swift
//  NEDnsProxyTest-Extension
//
//  Created by Daniel Karzel on 3/9/2025.
//

import Foundation
import Network

let networkExtensionId = "com.saasyan.test."

enum ConnectionError: Error {
  case incompleteRead
  case connectionCancelled
}

extension NWConnection {
  /// Async wrapper to establish a connection and wait for NWConnection.State.ready
  func establish() async throws {
    /// The internal dispatch queue
    ///
    /// Each connection has its own queue; the same label won't re-use the queue, it will be a separate instance.
    let queue = DispatchQueue(
      label: "\(networkExtensionId).queue", qos: .userInitiated)

    let orig_handler = self.stateUpdateHandler
    defer {
      self.stateUpdateHandler = orig_handler
    }
    try await withCheckedThrowingContinuation { continuation in
      self.stateUpdateHandler = { state in
        switch state {
        case .ready:
          continuation.resume()
        case .waiting(let err):
          continuation.resume(with: .failure(err))
        case .failed(let err):
          continuation.resume(with: .failure(err))
        case .cancelled:
          continuation.resume(with: .failure(ConnectionError.connectionCancelled))
        default:
          break
        }
      }
      self.start(queue: queue)
    }
  }

  /// An async/await wrapper for NWConnection.send
  func sendAsync(content: Data?, isComplete: Bool = true) async throws {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, Error>) -> Void in
      self.send(
        content: content, isComplete: isComplete,
        completion: .contentProcessed { error in
          if let error = error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume(returning: ())
          }
        })
    }
  }

  // An async/await wrapper for NWConnection.receiveMessage
  func receiveMessageAsync() async throws -> Data? {
    try await withCheckedThrowingContinuation { continuation in
      self.receiveMessage(completion: { data, context, _, error in
        if error != nil {
          return continuation.resume(throwing: error!)
        }

        continuation.resume(returning: data)
      })
    }
  }

  // An async/await wrapper for NWConnection.receive
  func receiveAsync() async throws -> Data? {
    try await withCheckedThrowingContinuation { continuation in
      self.receive(
        minimumIncompleteLength: 1, maximumLength: 1024,
        completion: { data, context, _, error in
          if error != nil {
            return continuation.resume(throwing: error!)
          }

          continuation.resume(returning: data)
        })
    }
  }
}
