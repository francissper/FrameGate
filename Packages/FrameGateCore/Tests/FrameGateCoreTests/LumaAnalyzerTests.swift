//
//  LumaAnalyzerTests.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 12/09/26.
//

import XCTest
import CoreVideo
@testable import FrameGateCore

final class LumaAnalyzerTests: XCTestCase {

    private let size = CGSize(width: 320, height: 240)
    private var whole: CGRect { CGRect(origin: .zero, size: size) }

    private func buffer(_ pattern: PatternGenerator.Pattern) throws -> CVPixelBuffer {
        try XCTUnwrap(PatternGenerator.makeBuffer(pattern, size: size))
    }

    private func measure(_ pattern: PatternGenerator.Pattern,
                         region: CGRect? = nil) throws -> FrameMetrics {
        let analyzer = LumaAnalyzer()
        let frame = try buffer(pattern)
        // First call establishes the motion baseline; measure the second.
        _ = analyzer.analyze(frame, region: region ?? whole)
        return try XCTUnwrap(analyzer.analyze(frame, region: region ?? whole))
    }
}

// MARK: - Sharpness

extension LumaAnalyzerTests {

    func testTheReferenceCheckerboardDefinesTheBaseline() throws {
        let metrics = try measure(.sharp)

        XCTAssertEqual(metrics.sharpness, 1.0, accuracy: 0.15,
                       "the reference pattern is what the baseline was measured on")
    }

    func testARampReadsAsUnsharp() throws {
        let metrics = try measure(.blurred)

        XCTAssertLessThan(metrics.sharpness, 0.05,
                          "neighbours differ by at most one level")
    }

    func testAFlatFieldHasNoSharpnessAtAll() throws {
        let metrics = try measure(.dark)

        XCTAssertEqual(metrics.sharpness, 0, accuracy: 0.001)
    }
}

// MARK: - Region isolation

extension LumaAnalyzerTests {

    func testMovingTheRegionAcrossTheMidlineFlipsTheVerdict() throws {
        let left = CGRect(x: 0, y: 0, width: size.width * 0.45, height: size.height)
        let right = CGRect(x: size.width * 0.55, y: 0,
                           width: size.width * 0.45, height: size.height)

        let sharpSide = try measure(.sharpLeftHalf, region: left)
        let flatSide = try measure(.sharpLeftHalf, region: right)

        XCTAssertGreaterThan(sharpSide.sharpness, 0.5)
        XCTAssertLessThan(flatSide.sharpness, 0.05)

        // Exposure is the same on both sides, so sharpness is the only difference.
        XCTAssertEqual(sharpSide.meanLuma, flatSide.meanLuma, accuracy: 0.05)
    }

    func testOnlyThePixelsInsideTheRegionAreRead() throws {
        let leftQuarter = CGRect(x: 0, y: 0, width: size.width * 0.25, height: size.height)
        let wholeFrame = try measure(.sharpLeftHalf)
        let quarter = try measure(.sharpLeftHalf, region: leftQuarter)

        XCTAssertGreaterThan(quarter.sharpness, wholeFrame.sharpness,
                             "the whole frame averages in the flat half")
    }
}

// MARK: - Exposure and motion

extension LumaAnalyzerTests {

    func testExposureSeparatesCrushedFromBlownPixels() throws {
        let dark = try measure(.dark)
        XCTAssertEqual(dark.meanLuma, 24.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(dark.crushedFraction, 0, accuracy: 0.001,
                       "24 is dark but above the crush threshold")
        XCTAssertEqual(dark.blownFraction, 0, accuracy: 0.001)
    }

    func testAnIdenticalFrameShowsNoMotion() throws {
        let analyzer = LumaAnalyzer()
        let frame = try buffer(.sharp)

        _ = analyzer.analyze(frame, region: whole)
        let second = try XCTUnwrap(analyzer.analyze(frame, region: whole))

        XCTAssertEqual(second.motion, 0, accuracy: 0.001)
    }

    func testTheFirstFrameReportsMaximumMotion() throws {
        let analyzer = LumaAnalyzer()
        let first = try XCTUnwrap(analyzer.analyze(try buffer(.sharp), region: whole))

        XCTAssertEqual(first.motion, 1.0,
                       "with nothing to compare against, be pessimistic")
    }

    func testADifferentFrameShowsMotion() throws {
        let analyzer = LumaAnalyzer()
        _ = analyzer.analyze(try buffer(.dark), region: whole)
        let moved = try XCTUnwrap(analyzer.analyze(try buffer(.sharp), region: whole))

        XCTAssertGreaterThan(moved.motion, 0.1)
    }

    func testResetMakesTheNextFrameReportMaximumMotion() throws {
        let analyzer = LumaAnalyzer()
        let frame = try buffer(.sharp)

        _ = analyzer.analyze(frame, region: whole)
        analyzer.reset()
        let afterReset = try XCTUnwrap(analyzer.analyze(frame, region: whole))

        XCTAssertEqual(afterReset.motion, 1.0)
    }
}
