//
//  PatternGeneratorTests.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 12/09/26.
//

import XCTest
import CoreVideo
@testable import FrameGateCore

final class PatternGeneratorTests: XCTestCase {

    private let size = CGSize(width: 320, height: 240)

    /// Reads the Y plane the same way the analyzer will: honouring bytesPerRow,
    /// with the lock held for exactly as long as the read.
    private func lumaStats(_ buffer: CVPixelBuffer,
                           columns: Range<Int>? = nil) -> (mean: Double, clipped: Double, maxStep: Int) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else {
            return (0, 0, 0)
        }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let plane = base.assumingMemoryBound(to: UInt8.self)
        let range = columns ?? 0..<width

        var total = 0
        var clipped = 0
        var maxStep = 0
        var count = 0

        for row in 0..<height {
            let line = plane + row * stride
            for column in range {
                let value = Int(line[column])
                total += value
                if value <= 5 || value >= 250 { clipped += 1 }
                if column > range.lowerBound {
                    maxStep = max(maxStep, abs(value - Int(line[column - 1])))
                }
                count += 1
            }
        }

        return (Double(total) / Double(count),
                Double(clipped) / Double(count),
                maxStep)
    }

    private func makeBuffer(_ pattern: PatternGenerator.Pattern) throws -> CVPixelBuffer {
        try XCTUnwrap(PatternGenerator.makeBuffer(pattern, size: size))
    }
}

// MARK: - Pattern properties

extension PatternGeneratorTests {

    func testSharpPatternIsWellExposedAndNeverClipped() throws {
        let stats = lumaStats(try makeBuffer(.sharp))

        XCTAssertEqual(stats.mean, 125, accuracy: 5,
                       "the reference frame must sit mid-exposure")
        XCTAssertEqual(stats.clipped, 0, accuracy: 0.001,
                       "16 and 235 are the video-range limits: sharp without clipping")
        XCTAssertEqual(stats.maxStep, 219,
                       "a checker edge is the full 16-to-235 swing")
    }

    func testBlurredPatternHasNoMeasurableGradient() throws {
        let stats = lumaStats(try makeBuffer(.blurred))

        XCTAssertLessThanOrEqual(stats.maxStep, 1,
                                 "a ramp spreads its range so neighbours barely differ")
        XCTAssertEqual(stats.mean, 125, accuracy: 10,
                       "blurred must fail sharpness only, not exposure")
        XCTAssertEqual(stats.clipped, 0, accuracy: 0.001)
    }

    func testDarkPatternIsUnderexposedWithoutCrushing() throws {
        let stats = lumaStats(try makeBuffer(.dark))

        XCTAssertEqual(stats.mean, 24, accuracy: 1)
        XCTAssertEqual(stats.maxStep, 0, "a flat field has no gradient at all")
        XCTAssertEqual(stats.clipped, 0, accuracy: 0.001,
                       "24 is dark but above the crush threshold, so exposure is isolated")
    }

    func testHalfSharpPatternSplitsExactlyAtTheMidline() throws {
        let buffer = try makeBuffer(.sharpLeftHalf)
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)

        let left = lumaStats(buffer, columns: 0..<(width / 2 - 1))
        let right = lumaStats(buffer, columns: (width / 2 + 1)..<width)

        XCTAssertEqual(left.maxStep, 219, "the left half carries the checker")
        XCTAssertEqual(right.maxStep, 0, "the right half is flat")
        XCTAssertEqual(right.mean, 128, accuracy: 1,
                       "flat grey, so the two halves differ in sharpness alone")
    }
}
