//
//  PlanParserTests.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 12/09/26.
//

import XCTest
@testable import FrameGateCore

final class PlanParserTests: XCTestCase {

    private func load(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            "fixture \(name).json not found in the test bundle"
        )
        return try Data(contentsOf: url)
    }

    private func parseMalformed() throws -> (plan: Plan, diagnostics: [Diagnostic]) {
        let result = PlanParser().parse(try load("plan_malformed"))
        guard case .success(let plan, let diagnostics) = result else {
            throw XCTSkip("expected the malformed plan to load with usable steps")
        }
        return (plan, diagnostics)
    }

    // MARK: - Happy path

    func testValidPlanLoadsEveryStepWithoutDiagnostics() throws {
        let result = PlanParser().parse(try load("plan_valid"))
        guard case .success(let plan, let diagnostics) = result else {
            return XCTFail("expected the valid plan to load")
        }

        XCTAssertEqual(plan.id, "warehouse-intake-v1")
        XCTAssertEqual(plan.steps.map(\.id), ["front-label", "serial-number", "overview"])
        XCTAssertTrue(diagnostics.isEmpty)
    }

    func testStepOrderIsPreserved() throws {
        let (plan, _) = try parseMalformed()
        XCTAssertEqual(plan.steps.map(\.id), ["front-label", "serial-number", "overview"])
    }

    // MARK: - Nine malformation cases

    // 1 — timestamp without a timezone
    func testTimestampWithoutTimezoneIsReadAsUTC() throws {
        let (plan, diagnostics) = try parseMalformed()

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let components = utc.dateComponents([.year, .month, .day, .hour, .minute], from: plan.createdAt)

        XCTAssertEqual(components.hour, 4)
        XCTAssertEqual(components.minute, 30)
        XCTAssertTrue(diagnostics.contains { $0.severity == .info && $0.message.contains("timezone") })
    }

    // 2 — nullable present as null
    func testNullLabelFallsBackToTheStepID() throws {
        let (plan, _) = try parseMalformed()
        let step = try XCTUnwrap(plan.steps.first { $0.id == "serial-number" })
        XCTAssertEqual(step.label, "serial-number")
    }

    // 3 — nullable absent entirely
    func testAbsentLabelFallsBackToTheStepID() throws {
        let (plan, _) = try parseMalformed()
        let step = try XCTUnwrap(plan.steps.first { $0.id == "overview" })
        XCTAssertEqual(step.label, "overview")
    }

    // 4 — number sent as a string
    func testNumericStringIsCoercedWithADiagnostic() throws {
        let (plan, diagnostics) = try parseMalformed()
        let step = try XCTUnwrap(plan.steps.first { $0.id == "serial-number" })

        XCTAssertEqual(step.holdFrames, 12)
        XCTAssertTrue(diagnostics.contains { $0.stepID == "serial-number" && $0.severity == .info })
    }

    // 5 — mixed key casing
    func testKeysAreMatchedRegardlessOfCasing() throws {
        let (plan, _) = try parseMalformed()
        let overview = try XCTUnwrap(plan.steps.first { $0.id == "overview" })

        XCTAssertEqual(overview.holdFrames, 5)       // came in as "HoldFrames"
        XCTAssertEqual(overview.roi.width, 0.90)     // came in as "ROI"
    }

    // 6 — unknown keys
    func testUnknownKeysAreIgnoredButReported() throws {
        let (plan, diagnostics) = try parseMalformed()

        XCTAssertTrue(plan.steps.contains { $0.id == "serial-number" })
        XCTAssertTrue(diagnostics.contains {
            $0.stepID == "serial-number" && $0.message.contains("priority")
        })
    }

    // 7 — duplicate step id
    func testDuplicateIDKeepsTheFirstOccurrence() throws {
        let (plan, diagnostics) = try parseMalformed()
        let matches = plan.steps.filter { $0.id == "front-label" }

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.roi.x, 0.15)   // the first, not the 0.20 duplicate
        XCTAssertTrue(diagnostics.contains {
            $0.stepID == "front-label" && $0.severity == .warning
        })
    }

    // 8 — unknown step kind
    func testUnknownKindSkipsTheStep() throws {
        let (plan, diagnostics) = try parseMalformed()

        XCTAssertFalse(plan.steps.contains { $0.id == "damage-close-up" })
        XCTAssertTrue(diagnostics.contains {
            $0.stepID == "damage-close-up" && $0.severity == .warning
        })
    }

    // 9 — declared object that is null
    func testNullROISkipsTheStep() throws {
        let (plan, diagnostics) = try parseMalformed()

        XCTAssertFalse(plan.steps.contains { $0.id == "packaging" })
        XCTAssertTrue(diagnostics.contains {
            $0.stepID == "packaging" && $0.severity == .warning
        })
    }

    // 10 — decimal that does not convert
    func testUnparseableDecimalSkipsTheStepWithoutApplyingADefault() throws {
        let (plan, diagnostics) = try parseMalformed()

        XCTAssertFalse(plan.steps.contains { $0.id == "barcode" })
        XCTAssertTrue(diagnostics.contains {
            $0.stepID == "barcode" && $0.severity == .warning
        })
    }

    // MARK: - Threshold semantics

    // the documented default for a missing threshold half
    func testMissingExitFallsBackToEnter() throws {
        let (plan, _) = try parseMalformed()
        let overview = try XCTUnwrap(plan.steps.first { $0.id == "overview" })

        XCTAssertEqual(overview.thresholds.sharpness.enter, Decimal(string: "0.40"))
        XCTAssertEqual(overview.thresholds.sharpness.exit, Decimal(string: "0.40"))
    }

    func testMissingMetricThresholdUsesDefaultWithoutDroppingStep() throws {
        let (plan, diagnostics) = try parseMalformed()

        let overview = try XCTUnwrap(
            plan.steps.first {
                $0.id == "overview"
            }
        )

        XCTAssertEqual(
            overview.thresholds.motion.enter,
            Decimal(2) / Decimal(100)
        )

        XCTAssertEqual(
            overview.thresholds.motion.exit,
            Decimal(4) / Decimal(100)
        )

        XCTAssertTrue(
            diagnostics.contains {
                $0.stepID == "overview"
                    && $0.severity == .info
                    && $0.message.contains("motion threshold missing")
            }
        )
    }

    // the decimal never passes through a Double
    func testThresholdsKeepDecimalPrecision() throws {
        let (plan, _) = try parseMalformed()
        let step = try XCTUnwrap(plan.steps.first { $0.id == "front-label" })

        let enter = step.thresholds.motion.enter    // 0.02
        let exit = step.thresholds.motion.exit      // 0.04
        let twice = enter + enter

        XCTAssertEqual(twice, exit)
    }

    // MARK: - Hard failures

    func testInvalidJSONFailsTheWholePlan() {
        let result = PlanParser().parse(Data("{ not json".utf8))
        guard case .failure(let error) = result else {
            return XCTFail("expected a hard failure")
        }
        XCTAssertEqual(error, .malformedJSON)
    }

    func testMissingStepsKeyFailsTheWholePlan() {
        let json = #"{ "planId": "x", "createdAt": "2026-09-12T04:30:00Z" }"#
        let result = PlanParser().parse(Data(json.utf8))
        guard case .failure(let error) = result else {
            return XCTFail("expected a hard failure")
        }
        XCTAssertEqual(error, .missingSteps)
    }

    func testAPlanWhereNoStepSurvivesFailsHard() {
        let json = #"""
        { "planId": "x", "createdAt": "2026-09-12T04:30:00Z",
          "steps": [ { "id": "a", "kind": "unknown" } ] }
        """#
        let result = PlanParser().parse(Data(json.utf8))
        guard case .failure(let error) = result else {
            return XCTFail("expected a hard failure")
        }
        XCTAssertEqual(error, .noUsableSteps)
    }
}
