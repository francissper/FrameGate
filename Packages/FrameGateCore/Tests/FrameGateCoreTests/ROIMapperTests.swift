//
//  ROIMapperTests.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 12/09/26.
//

import XCTest
import CoreGraphics
@testable import FrameGateCore

final class ROIMapperTests: XCTestCase {

    /// A 1920x1080 sensor buffer, the usual landscape-native shape.
    private let buffer = CGSize(width: 1920, height: 1080)
    /// A portrait iPhone view in points.
    private let view = CGSize(width: 390, height: 844)

    private func region(_ x: Double, _ y: Double,
                        _ width: Double, _ height: Double) throws -> NormalizedRegion {
        try XCTUnwrap(NormalizedRegion(x: x, y: y, width: width, height: height))
    }

    /// Every combination of the inputs that vary independently.
    private func everyCombination(
        _ body: (SensorRotation, Bool, DisplayOrientation, FillMode) throws -> Void
    ) rethrows {
        for rotation in SensorRotation.allCases {
            for mirrored in [false, true] {
                for orientation in DisplayOrientation.allCases {
                    for fill in FillMode.allCases {
                        try body(rotation, mirrored, orientation, fill)
                    }
                }
            }
        }
    }

    private func map(
        _ region: NormalizedRegion,
        _ rotation: SensorRotation,
        _ mirrored: Bool,
        _ orientation: DisplayOrientation,
        _ fill: FillMode
    ) -> MappedRegion {
        ROIMapper.map(region,
                      bufferSize: buffer,
                      sensorRotation: rotation,
                      mirrored: mirrored,
                      displayOrientation: orientation,
                      viewSize: view,
                      fillMode: fill)
    }
}

// MARK: - Properties

extension ROIMapperTests {

    func testBufferRectNeverLeavesTheBuffer() throws {
        let roi = try region(0.15, 0.30, 0.70, 0.25)
        let bounds = CGRect(origin: .zero, size: buffer)

        try everyCombination { rotation, mirrored, orientation, fill in
            let mapped = map(roi, rotation, mirrored, orientation, fill)
            XCTAssertTrue(
                bounds.contains(mapped.buffer),
                "\(mapped.buffer) escaped the buffer at \(rotation)/\(mirrored)/\(orientation)/\(fill)"
            )
        }
    }

    func testACentredRegionStaysCentredInTheBuffer() throws {
        let centred = try region(0.25, 0.25, 0.50, 0.50)
        let bufferCentre = CGPoint(x: buffer.width / 2, y: buffer.height / 2)

        try everyCombination { rotation, mirrored, orientation, fill in
            let mapped = map(centred, rotation, mirrored, orientation, fill)
            XCTAssertEqual(mapped.buffer.midX, bufferCentre.x, accuracy: 0.5)
            XCTAssertEqual(mapped.buffer.midY, bufferCentre.y, accuracy: 0.5)
        }
    }

    func testRotationPreservesTheProportionOfTheBufferCovered() throws {
        let roi = try region(0.15, 0.30, 0.70, 0.25)
        let bufferArea = buffer.width * buffer.height
        let expected = 0.70 * 0.25

        try everyCombination { rotation, mirrored, orientation, fill in
            let mapped = map(roi, rotation, mirrored, orientation, fill)
            let covered = (mapped.buffer.width * mapped.buffer.height) / bufferArea
            XCTAssertEqual(covered, expected, accuracy: 0.001,
                           "area changed at \(rotation)/\(mirrored)")
        }
    }

    func testMirroringTwiceReturnsTheOriginal() throws {
        let roi = try region(0.10, 0.20, 0.30, 0.40)

        for rotation in SensorRotation.allCases {
            let plain = map(roi, rotation, false, .portrait, .aspectFill)
            let mirrored = map(roi, rotation, true, .portrait, .aspectFill)

            // A mirrored rect is the plain one reflected across the buffer's centre.
            let reflected = CGRect(
                x: buffer.width - plain.buffer.maxX,
                y: plain.buffer.minY,
                width: plain.buffer.width,
                height: plain.buffer.height
            )
            XCTAssertEqual(mirrored.buffer.minX, reflected.minX, accuracy: 0.5)
            XCTAssertEqual(mirrored.buffer.width, reflected.width, accuracy: 0.5)
        }
    }

    func testAspectFitKeepsTheOutlineInsideTheView() throws {
        let roi = try region(0.05, 0.05, 0.90, 0.90)
        let bounds = CGRect(origin: .zero, size: view)

        try everyCombination { rotation, mirrored, orientation, _ in
            let mapped = map(roi, rotation, mirrored, orientation, .aspectFit)
            XCTAssertTrue(
                bounds.contains(mapped.view),
                "\(mapped.view) escaped the view at \(rotation)/\(orientation)"
            )
        }
    }
}

// MARK: - Concrete cases

extension ROIMapperTests {

    func testIdentityMappingPutsTheRegionWhereTheNumbersSay() throws {
        let roi = try region(0.25, 0.50, 0.50, 0.25)
        let mapped = map(roi, .deg0, false, .portrait, .aspectFill)

        // Origin top-left: x 0.25 of 1920, y 0.50 of 1080.
        XCTAssertEqual(mapped.buffer.minX, 480, accuracy: 0.5)
        XCTAssertEqual(mapped.buffer.minY, 540, accuracy: 0.5)
        XCTAssertEqual(mapped.buffer.width, 960, accuracy: 0.5)
        XCTAssertEqual(mapped.buffer.height, 270, accuracy: 0.5)
    }

    func testNinetyDegreesSwapsTheAxes() throws {
        // A wide, short band across the top.
        let band = try region(0.0, 0.0, 1.0, 0.20)
        let mapped = map(band, .deg90, false, .portrait, .aspectFill)

        // Rotated, the band becomes a tall, narrow strip down one side.
        XCTAssertEqual(mapped.buffer.width, buffer.width * 0.20, accuracy: 0.5)
        XCTAssertEqual(mapped.buffer.height, buffer.height, accuracy: 0.5)
    }

    func testMirroringFlipsHorizontallyOnly() throws {
        let left = try region(0.0, 0.40, 0.20, 0.20)
        let mapped = map(left, .deg0, true, .portrait, .aspectFill)

        // A region hugging the left edge lands against the right edge.
        XCTAssertEqual(mapped.buffer.maxX, buffer.width, accuracy: 0.5)
        XCTAssertEqual(mapped.buffer.minY, 1080 * 0.40, accuracy: 0.5)
    }
}

// MARK: - Outline and measurement agreement

extension ROIMapperTests {

  func testTheDrawnRectAndTheMeasuredRectDescribeTheSameRegion() throws {
      let leftThird = try region(0.0, 0.25, 0.33, 0.50)

      try everyCombination { rotation, mirrored, orientation, fill in
          let mapped = map(leftThird, rotation, mirrored, orientation, fill)

          XCTAssertGreaterThan(mapped.buffer.width, 0, "buffer rect is degenerate")
          XCTAssertGreaterThan(mapped.view.width, 0, "view rect is degenerate")

          let bufferOriginRatio = mapped.buffer.midX / buffer.width
          let viewOriginRatio = mapped.view.midX / view.width

          XCTAssertEqual(bufferOriginRatio, viewOriginRatio, accuracy: 0.02,
                         "outline and measurement diverged at \(rotation)/\(orientation)/\(fill)")
      }
  }
}
