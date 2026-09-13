//
//  CaptureRecord.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 13/09/26.
//

import Foundation

/// What a capture looks like to the queue. Deliberately only three states:
/// there is no persisted `uploading`, so after a crash everything that was in
/// flight is already `pending` with no recovery pass to run.
public enum UploadStatus: String, Sendable, Equatable {
    case pending
    case uploaded
    case failed
}

public struct CaptureRecord: Equatable, Sendable {
    /// Client-generated once, at the moment the shutter fires, and never again.
    /// A timeout leaves the outcome unknown, so the retry must carry the same
    /// key for the server to recognise it.
    public let captureID: UUID
    public let manifestPath: String
    public let framePath: String
    public var status: UploadStatus
    public var attempts: Int
    /// When the drain may try again. Nil while uploaded or failed.
    public var nextAttemptAt: Date?

    public init(captureID: UUID,
                manifestPath: String,
                framePath: String,
                status: UploadStatus = .pending,
                attempts: Int = 0,
                nextAttemptAt: Date? = nil) {
        self.captureID = captureID
        self.manifestPath = manifestPath
        self.framePath = framePath
        self.status = status
        self.attempts = attempts
        self.nextAttemptAt = nextAttemptAt
    }
}
