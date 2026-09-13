//
//  FakeTransport.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 13/09/26.
//

import Foundation
import os

/// One line of the request log. This is what proves send-once: a key that
/// appears twice with a `stored` outcome would mean the shot went up twice.
public struct TransportLogEntry: Equatable, Sendable {
    public let idempotencyKey: UUID
    public let attempt: Int
    public let outcome: UploadOutcome
}

/// A transport driven by a scripted list of outcomes rather than a network.
/// Each capture gets its own position in the script, so the first shot can be
/// made to fail four times while later ones succeed immediately.
public final class FakeTransport: UploadTransport, @unchecked Sendable {

    private struct State {
        var attemptsByKey: [UUID: Int] = [:]
        var log: [TransportLogEntry] = []
    }

    private let script: [UploadOutcome]
    private let fallback: UploadOutcome
    private let protected = OSAllocatedUnfairLock(initialState: State())

    /// - Parameters:
    ///   - script: outcomes for the first shot, in order.
    ///   - thereafter: what every attempt beyond the script returns.
    public init(script: [UploadOutcome],
                thereafter: UploadOutcome = .stored(duplicate: false)) {
        self.script = script
        self.fallback = thereafter
    }

    /// The brief's suggested script for the first shot.
    public static var suggestedScript: FakeTransport {
        FakeTransport(script: [
            .retryable(retryAfter: nil),   // 503
            .retryable(retryAfter: nil),   // 503
            .timedOut,                      // no response at all
            .retryable(retryAfter: nil),   // 500
            .stored(duplicate: false)      // 201
        ])
    }

    public func send(manifest: Data,
                     frame: Data,
                     idempotencyKey: UUID) async -> UploadOutcome {
        protected.withLock { state in
            let attempt = (state.attemptsByKey[idempotencyKey] ?? 0) + 1
            state.attemptsByKey[idempotencyKey] = attempt

            let outcome = attempt <= script.count ? script[attempt - 1] : fallback
            state.log.append(TransportLogEntry(idempotencyKey: idempotencyKey,
                                               attempt: attempt,
                                               outcome: outcome))
            return outcome
        }
    }

    /// Every request that was made, in order.
    public var requests: [TransportLogEntry] {
        protected.withLock { $0.log }
    }
}
