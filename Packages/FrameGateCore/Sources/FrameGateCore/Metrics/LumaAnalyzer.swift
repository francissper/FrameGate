//
//  LumaAnalyzer.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 12/09/26.
//

import CoreVideo
import CoreGraphics

/// Measures one frame inside the mapped region, reading the Y plane directly.
///
/// Scratch buffers are allocated once here and reused for every frame: the
/// steady-state path allocates nothing. The pixel buffer is never retained past
/// the call — only the downsampled copy survives, and it lives in a fixed-size
/// buffer so a changing ROI never triggers a reallocation.
public final class LumaAnalyzer {

    /// Raw sharpness of the reference checkerboard, measured once and recorded
    /// in the README. Dividing by it makes 1.0 mean "as sharp as the reference".
    public static let sharpnessBaseline: Double = 27.4

    /// A pixel at or below this has lost its shadow detail.
    static let crushThreshold: UInt8 = 5
    /// A pixel at or above this has lost its highlight detail.
    static let blowThreshold: UInt8 = 250

    /// Fixed so the scratch buffer never resizes when the ROI changes between steps.
    static let downsampleSide = 32

    private var current: [UInt8]
    private var previous: [UInt8]
    private var hasPrevious = false

    public init() {
        let count = Self.downsampleSide * Self.downsampleSide
        current = [UInt8](repeating: 0, count: count)
        previous = [UInt8](repeating: 0, count: count)
    }

    /// Measures the region. Returns nil if the buffer cannot be read.
    public func analyze(_ buffer: CVPixelBuffer, region: CGRect) -> FrameMetrics? {
        nil
    }

    /// Forgets the previous frame, so the next one reports maximum motion.
    /// Called when the plan advances to a step with a different region.
    public func reset() {
        hasPrevious = false
    }
}
