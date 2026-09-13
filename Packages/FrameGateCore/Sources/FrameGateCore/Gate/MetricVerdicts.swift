//
//  MetricVerdicts.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 13/09/26.
//

/// Whether each metric currently passes. Carried between frames: that is what
/// makes the hysteresis band work.
public struct MetricVerdicts: Equatable, Sendable {
    public var sharpness: Bool
    public var meanLuma: Bool
    public var clipping: Bool
    public var motion: Bool

    public init(sharpness: Bool, meanLuma: Bool, clipping: Bool, motion: Bool) {
        self.sharpness = sharpness
        self.meanLuma = meanLuma
        self.clipping = clipping
        self.motion = motion
    }

    /// Nothing measured yet, so nothing passes.
    public static let unmeasured = MetricVerdicts(
        sharpness: false, meanLuma: false, clipping: false, motion: false
    )

    public var allPass: Bool {
        sharpness && meanLuma && clipping && motion
    }

    public var failures: Set<BlockReason> {
        var reasons: Set<BlockReason> = []
        if !sharpness { reasons.insert(.sharpness) }
        if !meanLuma { reasons.insert(.underexposed) }
        if !clipping { reasons.insert(.overexposed) }
        if !motion { reasons.insert(.motion) }
        return reasons
    }
}
