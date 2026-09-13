//
//  UploadTransport.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 13/09/26.
//

import Foundation

/// What the server said about one attempt.
public enum UploadOutcome: Equatable, Sendable {
    /// 201, or 200 with the duplicate flag: the server already had this key.
    /// Both mean stored — do not send again.
    case stored(duplicate: Bool)
    /// 503 or 500. `retryAfter` carries the server's hint when it sent one.
    case retryable(retryAfter: TimeInterval?)
    /// No response at all. Retryable, but the shot may in fact have been stored,
    /// which is exactly why the idempotency key must not change between attempts.
    case timedOut
    /// 422. No further automatic attempts; the user can retry from the Queue.
    case rejected
}

/// The seam over the network. The fake implements this for tests; the real one
/// wraps URLSession and points at the mock server.
public protocol UploadTransport: Sendable {
    /// Sends one attempt. The key is identical across every retry of this shot.
    func send(manifest: Data,
              frame: Data,
              idempotencyKey: UUID) async -> UploadOutcome
}
