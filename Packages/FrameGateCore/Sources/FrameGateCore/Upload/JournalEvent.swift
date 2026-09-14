//
//  JournalEvent.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 13/09/26.
//

import Foundation

/// One line of the journal. State is never overwritten — it is derived by
/// replaying these in order, which is what makes a half-written line survivable:
/// the torn line is discarded and everything before it still stands.
public enum JournalEvent: Equatable, Sendable {
    case captured(captureID: UUID, manifestFilename: String, frameFilename: String, at: Date)
    case attempted(captureID: UUID, attempt: Int, at: Date)
    case retryScheduled(captureID: UUID, nextAttemptAt: Date, at: Date)
    case uploaded(captureID: UUID, at: Date)
    case failed(captureID: UUID, at: Date)
    case manuallyRetried(captureID: UUID, at: Date)

    public var captureID: UUID {
        switch self {
        case .captured(let id, _, _, _),
             .attempted(let id, _, _),
             .retryScheduled(let id, _, _),
             .uploaded(let id, _),
             .failed(let id, _),
             .manuallyRetried(let id, _):
            return id
        }
    }
}
