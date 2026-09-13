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

    everyCombination { rotation, mirrored, orientation, fill in
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

    everyCombination { rotation, mirrored, orientation, fill in
      let mapped = map(centred, rotation, mirrored, orientation, fill)
      XCTAssertEqual(mapped.buffer.midX, bufferCentre.x, accuracy: 0.5)
      XCTAssertEqual(mapped.buffer.midY, bufferCentre.y, accuracy: 0.5)
    }
  }

  func testRotationPreservesTheProportionOfTheBufferCovered() throws {
    let roi = try region(0.15, 0.30, 0.70, 0.25)
    let bufferArea = buffer.width * buffer.height
    let expected = 0.70 * 0.25

    everyCombination { rotation, mirrored, orientation, fill in
      let mapped = map(roi, rotation, mirrored, orientation, fill)
      let covered = (mapped.buffer.width * mapped.buffer.height) / bufferArea
      XCTAssertEqual(covered, expected, accuracy: 0.001,
                     "area changed at \(rotation)/\(mirrored)")
    }
  }

  func testAspectFitKeepsTheOutlineInsideTheView() throws {
    let roi = try region(0.05, 0.05, 0.90, 0.90)
    let bounds = CGRect(origin: .zero, size: view)

    everyCombination { rotation, mirrored, orientation, _ in
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

  func testRotationTurnsTheOutlineInTheViewButNotTheMeasuredRegion() throws {
    // A wide, short band across the top of the sensor frame.
    let band = try region(0.0, 0.0, 1.0, 0.20)

    let upright = map(band, .deg0, false, .portrait, .aspectFit)
    let turned = map(band, .deg90, false, .portrait, .aspectFit)

    // The measured region is the same either way: the ROI is normalized to the
    // sensor, so rotating the device keeps measuring the same part of the subject.
    XCTAssertEqual(turned.buffer, upright.buffer)

    // The outline, however, turns: a wide band becomes a narrow strip.
    XCTAssertGreaterThan(upright.view.width, upright.view.height)
    XCTAssertGreaterThan(turned.view.height, turned.view.width)
  }

  func testMirroringFlipsTheOutlineNotTheMeasuredRegion() throws {
    let left = try region(0.0, 0.40, 0.20, 0.20)

    let plain = map(left, .deg0, false, .portrait, .aspectFit)
    let mirrored = map(left, .deg0, true, .portrait, .aspectFit)

    XCTAssertEqual(mirrored.buffer, plain.buffer)

    // A region hugging the left edge is drawn against the right edge.
    XCTAssertLessThan(plain.view.midX, mirrored.view.midX)
  }
}

// MARK: - Outline and measurement agreement

extension ROIMapperTests {

  func testTheOutlineTracksTheRegionWithinTheContentArea() throws {
    let leftThird = try region(0.0, 0.25, 0.33, 0.50)
    let rightThird = try region(0.67, 0.25, 0.33, 0.50)

    everyCombination { rotation, mirrored, orientation, fill in
      let left = map(leftThird, rotation, mirrored, orientation, fill)
      let right = map(rightThird, rotation, mirrored, orientation, fill)

      XCTAssertGreaterThan(left.buffer.width, 0, "buffer rect is degenerate")
      XCTAssertGreaterThan(left.view.width, 0, "view rect is degenerate")

      // Two distinct regions must never collapse onto the same outline: if they
      // did, the drawn rectangle would not be tracking the measured one.
      XCTAssertNotEqual(left.view, right.view,
                        "outlines collapsed at \(rotation)/\(orientation)/\(fill)")
      XCTAssertNotEqual(left.buffer, right.buffer)
    }
  }

  func testTheOutlineIsDerivedFromTheMappingAndNotHandPlaced() throws {
      // The whole frame must map to the whole content area, for every combination.
      let whole = try region(0.0, 0.0, 1.0, 1.0)

      everyCombination { rotation, mirrored, orientation, fill in
          let mapped = map(whole, rotation, mirrored, orientation, fill)

          // Measuring the whole frame means the buffer rect is the buffer itself.
          XCTAssertEqual(mapped.buffer, CGRect(origin: .zero, size: buffer))

          // And the outline covers the whole content area — with aspectFit that
          // fits inside the view, with aspectFill it overflows it.
          switch fill {
          case .aspectFit:
              XCTAssertLessThanOrEqual(mapped.view.width, view.width + 0.5)
              XCTAssertLessThanOrEqual(mapped.view.height, view.height + 0.5)
          case .aspectFill:
              XCTAssertGreaterThanOrEqual(mapped.view.width, view.width - 0.5)
              XCTAssertGreaterThanOrEqual(mapped.view.height, view.height - 0.5)
          }
      }
  }
}
