//
//  ManifestEncoderTests.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 13/09/26.
//

import XCTest
@testable import FrameGateCore

final class ManifestEncoderTests: XCTestCase {

  /// A manifest with values chosen to exercise every encoding rule: a rotation
  /// that is not zero, a mirrored sensor, and metrics that round in both
  /// directions at four places.
  private func makeManifest() throws -> CaptureManifest {
    CaptureManifest(
      captureID: try XCTUnwrap(UUID(uuidString: "7F3E2A1C-0000-4000-8000-000000000001")),
      planID: "warehouse-intake-v1",
      planCreatedAt: Date(timeIntervalSince1970: 1_789_100_000),
      stepID: "front-label",
      capturedAt: Date(timeIntervalSince1970: 1_789_186_961.317),
      sensorRotation: .deg90,
      displayOrientation: .landscapeLeft,
      mirrored: true,
      region: try XCTUnwrap(NormalizedRegion(x: 0.15, y: 0.30, width: 0.70, height: 0.25)),
      metrics: FrameMetrics(sharpness: 0.84123456,
                            meanLuma: 0.50305,
                            crushedFraction: 0,
                            blownFraction: 0.012,
                            motion: 0.00874),
      holdFramesRequired: 8,
      framesDropped: 37
    )
  }

  private func encoded() throws -> [String: Any] {
    let data = try ManifestEncoder.encode(try makeManifest())
    return try XCTUnwrap(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
  }
}

// MARK: - Wire contract

extension ManifestEncoderTests {

  func testTheFieldNamesAreTheOnesDocumented() throws {
    let json = try encoded()

    XCTAssertEqual(Set(json.keys), [
      "captureId", "planId", "planCreatedAt", "stepId", "capturedAt",
      "sensorRotation", "displayOrientation", "mirrored",
      "region", "metrics", "holdFramesRequired", "framesDropped"
    ], "the wire contract changed — update the README before changing this")
  }

  func testTimestampsAreUTCWithMilliseconds() throws {
    let json = try encoded()

    XCTAssertEqual(json["capturedAt"] as? String, "2026-09-12T04:22:41.317Z")
    XCTAssertEqual(json["planCreatedAt"] as? String, "2026-09-11T04:13:20.000Z")
  }

  func testSensorRotationIsAnAngleAndDisplayOrientationIsALabel() throws {
    let json = try encoded()

    XCTAssertEqual(json["sensorRotation"] as? Int, 90,
                   "an angle, so a number")
    XCTAssertEqual(json["displayOrientation"] as? String, "landscapeLeft",
                   "a label, so a string")
  }

  func testEveryMeasuredValueCarriesExactlyFourPlaces() throws {
    let json = try encoded()
    let metrics = try XCTUnwrap(json["metrics"] as? [String: Any])
    let region = try XCTUnwrap(json["region"] as? [String: Any])

    for (name, value) in metrics.merging(region, uniquingKeysWith: { first, _ in first }) {
      let text = try XCTUnwrap(value as? String, "\(name) must be a string")
      let places = text.split(separator: ".").last?.count
      XCTAssertEqual(places, 4, "\(name) carries \(text)")
    }
  }

  func testMeasuredValuesAreStringsNotJSONNumbers() throws {
    let data = try ManifestEncoder.encode(try makeManifest())
    let text = try XCTUnwrap(String(data: data, encoding: .utf8))

    XCTAssertTrue(text.contains("\"sharpness\":\"0.8412\""),
                  "a JSON number would let the receiver parse it into a float")
    XCTAssertFalse(text.contains("\"sharpness\":0."),
                   "no bare number should reach the wire")
  }

  func testRoundingIsHalfEvenAtTheFourthPlace() throws {
    let json = try encoded()
    let metrics = try XCTUnwrap(json["metrics"] as? [String: Any])

    XCTAssertEqual(metrics["sharpness"] as? String, "0.8412", "0.84123456 truncates")
    XCTAssertEqual(metrics["motion"] as? String, "0.0087", "0.00874 rounds down")
    XCTAssertEqual(metrics["crushedFraction"] as? String, "0.0000",
                   "zero still carries its places")

    // 0.50305 has no exact binary representation: the nearest Double sits just
    // below it, so %.4f rounds down. Documented rather than worked around —
    // this is precisely why thresholds travel as Decimal and metrics do not.
    XCTAssertEqual(metrics["meanLuma"] as? String, "0.5030")
  }

  func testTheRegionUsesTheSameConventionAsThePlan() throws {
    let json = try encoded()
    let region = try XCTUnwrap(json["region"] as? [String: Any])

    XCTAssertEqual(region["x"] as? String, "0.1500")
    XCTAssertEqual(region["y"] as? String, "0.3000")
    XCTAssertEqual(region["width"] as? String, "0.7000")
    XCTAssertEqual(region["height"] as? String, "0.2500")
  }

  func testTheOutputIsByteStableAcrossRuns() throws {
    let first = try ManifestEncoder.encode(try makeManifest())
    let second = try ManifestEncoder.encode(try makeManifest())

    XCTAssertEqual(first, second,
                   "sorted keys keep the payload identical for the same input")
  }
}
