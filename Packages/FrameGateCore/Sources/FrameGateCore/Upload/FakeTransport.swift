//
//  FakeTransport.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 13/09/26.
//

import Foundation
import os

/// One line of the request log.
///
/// Repeated attempts for one capture intentionally reuse the same idempotency
/// key. A successful stored outcome for two different keys represents two
/// different captures, not a duplicate upload.
public struct TransportLogEntry: Equatable, Sendable {
    public let idempotencyKey: UUID
    public let attempt: Int
    public let outcome: UploadOutcome
}

/// A deterministic transport used by the queue tests.
///
/// The scripted outcomes apply only to the first capture observed by the
/// transport. Every later capture returns `thereafter` immediately, matching
/// the failure scenario required by the assessment.
public final class FakeTransport: UploadTransport, @unchecked Sendable {

    private struct State {
        var firstCaptureID: UUID?
        var attemptsByKey: [UUID: Int] = [:]
        var log: [TransportLogEntry] = []
    }

    private let script: [UploadOutcome]
    private let fallback: UploadOutcome
    private let protected = OSAllocatedUnfairLock(
        initialState: State()
    )

    /// - Parameters:
    ///   - script: Outcomes applied, in order, to the first capture only.
    ///   - thereafter: Outcome returned by captures after the first one, and
    ///     by attempts beyond the scripted sequence.
    public init(
        script: [UploadOutcome],
        thereafter: UploadOutcome = .stored(duplicate: false)
    ) {
        self.script = script
        fallback = thereafter
    }

    /// The failure sequence suggested by the assessment:
    /// 503, 503, timeout, 500, 201.
    public static var suggestedScript: FakeTransport {
        FakeTransport(
            script: [
                .retryable(retryAfter: nil),
                .retryable(retryAfter: nil),
                .timedOut,
                .retryable(retryAfter: nil),
                .stored(duplicate: false)
            ]
        )
    }

    public func send(
        manifest: Data,
        frame: Data,
        idempotencyKey: UUID
    ) async -> UploadOutcome {
        protected.withLock { state in
            if state.firstCaptureID == nil {
                state.firstCaptureID = idempotencyKey
            }

            let attempt =
                (state.attemptsByKey[idempotencyKey] ?? 0) + 1

            state.attemptsByKey[idempotencyKey] = attempt

            let outcome = outcome(
                for: idempotencyKey,
                attempt: attempt,
                firstCaptureID: state.firstCaptureID
            )

            state.log.append(
                TransportLogEntry(
                    idempotencyKey: idempotencyKey,
                    attempt: attempt,
                    outcome: outcome
                )
            )

            return outcome
        }
    }

    /// Every request made by the transport, in order.
    public var requests: [TransportLogEntry] {
        protected.withLock {
            $0.log
        }
    }
}

// MARK: - Outcome selection

private extension FakeTransport {

    func outcome(
        for captureID: UUID,
        attempt: Int,
        firstCaptureID: UUID?
    ) -> UploadOutcome {
        guard captureID == firstCaptureID else {
            return fallback
        }

        guard attempt <= script.count else {
            return fallback
        }

        return script[attempt - 1]
    }
}
