//
//  GateTests.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 13/09/26.
//

import XCTest
@testable import FrameGateCore

private struct GateFixture: Decodable {
    let thresholds: FixtureThresholds
    let cases: [FixtureCase]
}

private struct ThresholdPair: Decodable {
    let enter: String
    let exit: String

    var resolved: Threshold {
        Threshold(enter: Decimal(string: enter) ?? .zero,
                  exit: Decimal(string: exit) ?? .zero)
    }
}

private struct FixtureThresholds: Decodable {
    let sharpness: ThresholdPair
    let meanLuma: ThresholdPair
    let clippedFraction: ThresholdPair
    let motion: ThresholdPair

    var resolved: Thresholds {
        Thresholds(sharpness: sharpness.resolved,
                   meanLuma: meanLuma.resolved,
                   clippedFraction: clippedFraction.resolved,
                   motion: motion.resolved)
    }
}

private struct FixtureFrame: Decodable {
    let sharpness: Double
    let meanLuma: Double
    let clipped: Double
    let motion: Double
    let expect: String

    var metrics: FrameMetrics {
        FrameMetrics(sharpness: sharpness,
                     meanLuma: meanLuma,
                     crushedFraction: 0,
                     blownFraction: clipped,
                     motion: motion)
    }
}

private struct FixtureCase: Decodable {
    let name: String
    let holdFrames: Int
    let frames: [FixtureFrame]
}

final class GateTests: XCTestCase {}

// MARK: - Phase description

extension GateTests {

    /// Turns "holding:3" or "blocked:sharpness,motion" into something comparable.
    private func describe(_ phase: GatePhase) -> String {
        switch phase {
        case .armed:
            return "armed"
        case .fired:
            return "fired"
        case .holding(let count, _):
            return "holding:\(count)"
        case .blocked(let reasons):
            let names = BlockReason.allCases
                .filter { reasons.contains($0) }
                .map(\.rawValue)
                .joined(separator: ",")
            return "blocked:\(names)"
        }
    }

    private func loadSequences() throws -> GateFixture {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "gate_sequences",
                              withExtension: "json",
                              subdirectory: "Fixtures")
        )
        return try JSONDecoder().decode(GateFixture.self, from: Data(contentsOf: url))
    }
}

// MARK: - Fixture-driven sequences

extension GateTests {

    func testEverySequenceInTheFixtureBehavesAsSpecified() throws {
        let sequences = try loadSequences()
        let thresholds = sequences.thresholds.resolved

        for testCase in sequences.cases {
            var state = GateState()

            for (index, step) in testCase.frames.enumerated() {
                state = Gate.advance(state,
                                     metrics: step.metrics,
                                     thresholds: thresholds,
                                     holdFrames: testCase.holdFrames,
                                     stepCount: 1,
                                     tick: index)

                XCTAssertEqual(
                    describe(state.phase), step.expect,
                    "\(testCase.name) — frame \(index)"
                )
            }
        }
    }
}

// MARK: - Step transitions

extension GateTests {

    private var passing: FrameMetrics {
        FrameMetrics(sharpness: 0.80, meanLuma: 0.50,
                     crushedFraction: 0, blownFraction: 0.01, motion: 0.01)
    }

    private var failing: FrameMetrics {
        FrameMetrics(sharpness: 0.10, meanLuma: 0.50,
                     crushedFraction: 0, blownFraction: 0.01, motion: 0.01)
    }

    private var thresholds: Thresholds {
        get throws { try loadSequences().thresholds.resolved }
    }

    /// Runs frames until the gate arms, then fires.
    private func armAndFire(_ state: GateState,
                            stepCount: Int,
                            holdFrames: Int = 2,
                            from tick: Int = 0) throws -> GateState {
        var current = state
        var now = tick

        while current.phase != .armed {
            current = Gate.advance(current,
                                   metrics: passing,
                                   thresholds: try thresholds,
                                   holdFrames: holdFrames,
                                   stepCount: stepCount,
                                   tick: now)
            now += 1
            if now > tick + 20 { XCTFail("gate never armed"); return current }
        }
        return Gate.fire(current, tick: now)
    }

    func testFiringMovesToTheNextStepOnTheFollowingFrame() throws {
        let fired = try armAndFire(GateState(), stepCount: 3)
        XCTAssertEqual(fired.phase, .fired)
        XCTAssertEqual(fired.stepIndex, 0, "still on the step that fired")

        let next = Gate.advance(fired,
                                metrics: passing,
                                thresholds: try thresholds,
                                holdFrames: 2,
                                stepCount: 3,
                                tick: 99)

        XCTAssertEqual(next.stepIndex, 1, "the frame after firing moves on")
        XCTAssertFalse(next.isComplete)
    }

    func testTheRunStartsFreshOnTheNewStep() throws {
        let fired = try armAndFire(GateState(), stepCount: 3)

        // The frame after firing only advances: the new step has a different region,
        // so nothing has been measured for it yet.
        let advanced = Gate.advance(fired,
                                    metrics: passing,
                                    thresholds: try thresholds,
                                    holdFrames: 2,
                                    stepCount: 3,
                                    tick: 99)

        XCTAssertEqual(advanced.verdicts, .unmeasured,
                       "the previous step's verdicts say nothing about the new region")
        XCTAssertEqual(describe(advanced.phase), "blocked:sharpness,underexposed,overexposed,motion")

        // The next frame is the first one actually measured against the new step.
        let measured = Gate.advance(advanced,
                                    metrics: passing,
                                    thresholds: try thresholds,
                                    holdFrames: 2,
                                    stepCount: 3,
                                    tick: 100)

        XCTAssertEqual(describe(measured.phase), "holding:1",
                       "the run starts from zero on the new step")
    }

    func testFiringTheLastStepCompletesThePlan() throws {
        let fired = try armAndFire(GateState(stepIndex: 2), stepCount: 3)
        let after = Gate.advance(fired,
                                 metrics: passing,
                                 thresholds: try thresholds,
                                 holdFrames: 2,
                                 stepCount: 3,
                                 tick: 99)

        XCTAssertTrue(after.isComplete)
        XCTAssertEqual(after.stepIndex, 3, "one past the last step")
    }

    func testACompletePlanIgnoresFurtherFrames() throws {
        let fired = try armAndFire(GateState(stepIndex: 2), stepCount: 3)
        let complete = Gate.advance(fired, metrics: passing, thresholds: try thresholds,
                                    holdFrames: 2, stepCount: 3, tick: 99)
        let after = Gate.advance(complete, metrics: passing, thresholds: try thresholds,
                                 holdFrames: 2, stepCount: 3, tick: 100)

        XCTAssertEqual(after, complete, "nothing changes once the plan is done")
    }

    func testFiringIsIgnoredUnlessArmed() throws {
        let blocked = Gate.advance(GateState(),
                                   metrics: failing,
                                   thresholds: try thresholds,
                                   holdFrames: 4,
                                   stepCount: 1,
                                   tick: 0)

        XCTAssertEqual(Gate.fire(blocked, tick: 1), blocked,
                       "pressing a disabled shutter does nothing")
    }
}

// MARK: - Invariants

extension GateTests {

    func testBlockedIsNeverEmpty() throws {
        let sequences = try loadSequences()
        let thresholds = sequences.thresholds.resolved

        for testCase in sequences.cases {
            var state = GateState()
            for (index, step) in testCase.frames.enumerated() {
                state = Gate.advance(state, metrics: step.metrics,
                                     thresholds: thresholds,
                                     holdFrames: testCase.holdFrames,
                                     stepCount: 1, tick: index)

                if case .blocked(let reasons) = state.phase {
                    XCTAssertFalse(reasons.isEmpty,
                                   "\(testCase.name) — frame \(index): blocked with no reason")
                }
            }
        }
    }

    func testTheHUDAlwaysHasAReasonToShowWhileBlocked() throws {
        let blocked = Gate.advance(GateState(),
                                   metrics: failing,
                                   thresholds: try loadSequences().thresholds.resolved,
                                   holdFrames: 4,
                                   stepCount: 1,
                                   tick: 0)

        XCTAssertNotNil(blocked.blockingReason)
    }
}
