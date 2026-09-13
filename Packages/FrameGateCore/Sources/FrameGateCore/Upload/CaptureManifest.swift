//
//  CaptureManifest.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 13/09/26.
//

import Foundation

/// The JSON part of an upload. Describes what was captured: which plan and step
/// produced it, under what geometry, and what the frame measured when it fired.
///
/// Every decimal travels as a fixed-precision string. JSON numbers would let the
/// receiving end parse them into a float and hand back 0.8411999999999999, which
/// breaks equality and decimal columns alike; a string is the same value in every
/// language. It also makes the precision explicit — four places, always, where a
/// number could not distinguish 0.5 from 0.5000.
public struct CaptureManifest: Equatable, Sendable {
    /// Client-generated, identical across every retry of this shot.
    public let captureID: UUID
    public let planID: String
    public let planCreatedAt: Date
    public let stepID: String
    public let capturedAt: Date
    /// Degrees, one of 0, 90, 180, 270. An angle, so a number.
    public let sensorRotation: SensorRotation
    /// A label rather than an angle, so a string.
    public let displayOrientation: DisplayOrientation
    public let mirrored: Bool
    /// 0…1 of the sensor frame, origin top-left — the same convention the plan uses.
    public let region: NormalizedRegion
    public let metrics: FrameMetrics
    public let holdFramesRequired: Int
    /// How many frames the source dropped over the session. Context for quality:
    /// a shot taken while dropping heavily was taken under load.
    public let framesDropped: Int

    public init(captureID: UUID,
                planID: String,
                planCreatedAt: Date,
                stepID: String,
                capturedAt: Date,
                sensorRotation: SensorRotation,
                displayOrientation: DisplayOrientation,
                mirrored: Bool,
                region: NormalizedRegion,
                metrics: FrameMetrics,
                holdFramesRequired: Int,
                framesDropped: Int) {
        self.captureID = captureID
        self.planID = planID
        self.planCreatedAt = planCreatedAt
        self.stepID = stepID
        self.capturedAt = capturedAt
        self.sensorRotation = sensorRotation
        self.displayOrientation = displayOrientation
        self.mirrored = mirrored
        self.region = region
        self.metrics = metrics
        self.holdFramesRequired = holdFramesRequired
        self.framesDropped = framesDropped
    }
}
