//
//  FrameMetrics.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 12/09/26.
//

/// What one frame measured inside the mapped region. All values are normalized
/// so thresholds in the plan mean the same thing across devices.
public struct FrameMetrics: Equatable, Sendable {
    /// Mean neighbour difference, divided by the documented baseline.
    /// 1.0 means "as sharp as the reference checkerboard".
    public let sharpness: Double
    /// Mean luma over 0…1.
    public let meanLuma: Double
    /// Fraction of pixels at or below the crush threshold.
    public let crushedFraction: Double
    /// Fraction of pixels at or above the blow-out threshold.
    public let blownFraction: Double
    /// Mean absolute difference against the previous downsampled luma, over 0…1.
    /// The first frame has no predecessor and reports 1.0 — pessimistic, so the
    /// gate never arms on a frame it could not compare.
    public let motion: Double

    public init(sharpness: Double,
                meanLuma: Double,
                crushedFraction: Double,
                blownFraction: Double,
                motion: Double) {
        self.sharpness = sharpness
        self.meanLuma = meanLuma
        self.crushedFraction = crushedFraction
        self.blownFraction = blownFraction
        self.motion = motion
    }

    /// The plan carries a single `clippedFraction` threshold; the worse half wins.
    public var clippedFraction: Double {
        max(crushedFraction, blownFraction)
    }
}
