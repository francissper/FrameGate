//
//  PatternGenerator.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 12/09/26.
//

import CoreGraphics
import CoreVideo

/// Builds the synthetic frames the replay source plays back. Patterns are
/// generated rather than bundled so the test data is readable in the source:
/// exactly where the sharp edge sits, and exactly how dark the dark frame is.
public enum PatternGenerator {

    public enum Pattern: CaseIterable {
        /// Fine checkerboard across the whole frame: high sharpness everywhere.
        case sharp
        /// Smooth gradient: low sharpness everywhere.
        case blurred
        /// Uniformly dark: low mean luma, low sharpness.
        case dark
        /// Checkerboard on the left half, flat grey on the right. Moving the ROI
        /// across the midline must flip the verdict — this is the frame that
        /// proves the region drawn is the region measured.
        case sharpLeftHalf
    }

    /// Renders a pattern into a 420YpCbCr8BiPlanarFullRange buffer.
    /// Called once at startup; never on the frame path.
    public static func makeBuffer(_ pattern: Pattern, size: CGSize) -> CVPixelBuffer? {
        guard let buffer = allocateBuffer(size: size) else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        writeLuma(pattern, into: buffer)
        writeNeutralChroma(into: buffer)
        return buffer
    }
}

// MARK: - Buffer allocation and plane writing

private extension PatternGenerator {

    static func allocateBuffer(size: CGSize) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelBufferWidthKey: Int(size.width),
            kCVPixelBufferHeightKey: Int(size.height)
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(size.width),
                                         Int(size.height),
                                         kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                                         attributes as CFDictionary,
                                         &buffer)
        return status == kCVReturnSuccess ? buffer : nil
    }

    static func writeLuma(_ pattern: Pattern, into buffer: CVPixelBuffer) {
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let plane = base.assumingMemoryBound(to: UInt8.self)

        for row in 0..<height {
            let line = plane + row * stride
            for column in 0..<width {
                line[column] = luma(pattern, column: column, row: row,
                                    width: width, height: height)
            }
        }
    }

    /// Chroma is left neutral: the analyzer reads the Y plane only, so colour
    /// carries no information here.
    static func writeNeutralChroma(into buffer: CVPixelBuffer) {
        guard CVPixelBufferGetPlaneCount(buffer) > 1,
              let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) else { return }
        let height = CVPixelBufferGetHeightOfPlane(buffer, 1)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
        memset(base, 128, height * stride)
    }
}

// MARK: - Per-pixel luma

private extension PatternGenerator {

    /// Checker squares are 8px: small enough that a gradient operator sees a
    /// strong edge on almost every sample, large enough to survive subsampling.
    static let checkerSize = 8

    static func luma(_ pattern: Pattern,
                     column: Int, row: Int,
                     width: Int, height: Int) -> UInt8 {
        switch pattern {
        case .sharp:
            return checker(column: column, row: row)

        case .blurred:
            // A horizontal ramp: neighbouring pixels differ by at most one step,
            // so any gradient measure stays near zero.
            return UInt8(60 + (column * 130) / max(width - 1, 1))

        case .dark:
            return 24

        case .sharpLeftHalf:
            return column < width / 2 ? checker(column: column, row: row) : 128
        }
    }

    static func checker(column: Int, row: Int) -> UInt8 {
        let cell = (column / checkerSize + row / checkerSize) % 2
        return cell == 0 ? 16 : 235
    }
}
