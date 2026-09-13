//
//  Gate.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 13/09/26.
//

import Foundation

/// The gate decides when the shutter is enabled. A pure function from state and
/// measurements to a new state: no camera, no Combine, and no clock read inside
/// — the tick is passed in so a test can drive it frame by frame.
public enum Gate {

    public static func advance(_ state: GateState,
                               metrics: FrameMetrics,
                               thresholds: Thresholds,
                               holdFrames: Int,
                               stepCount: Int,
                               tick: Int) -> GateState {
        guard !state.isComplete else { return state }

        // A fired step is transient: the frame after it moves on.
        if case .fired = state.phase {
            return beginNextStep(after: state, stepCount: stepCount, tick: tick)
        }

        let verdicts = judge(metrics, against: thresholds, previous: state.verdicts)
        let phase = nextPhase(from: state.phase, verdicts: verdicts, holdFrames: holdFrames)

        return GateState(
            stepIndex: state.stepIndex,
            phase: phase,
            verdicts: verdicts,
            phaseChangedAt: phase == state.phase ? state.phaseChangedAt : tick,
            isComplete: false
        )
    }

    /// Called when the user presses the shutter. Only meaningful while armed.
    public static func fire(_ state: GateState, tick: Int) -> GateState {
        guard state.phase == .armed else { return state }

        return GateState(
            stepIndex: state.stepIndex,
            phase: .fired,
            verdicts: state.verdicts,
            phaseChangedAt: tick,
            isComplete: false
        )
    }
}

// MARK: - Hysteresis

private extension Gate {

    /// Applies the hysteresis band per metric. Inside the band a metric keeps
    /// whatever verdict it last had, which is what stops the shutter chattering
    /// when a value hovers on the threshold.
    static func judge(_ metrics: FrameMetrics,
                      against thresholds: Thresholds,
                      previous: MetricVerdicts) -> MetricVerdicts {
        MetricVerdicts(
            sharpness: higherIsBetter(metrics.sharpness,
                                      thresholds.sharpness,
                                      previous.sharpness),
            meanLuma: higherIsBetter(metrics.meanLuma,
                                     thresholds.meanLuma,
                                     previous.meanLuma),
            clipping: lowerIsBetter(metrics.clippedFraction,
                                    thresholds.clippedFraction,
                                    previous.clipping),
            motion: lowerIsBetter(metrics.motion,
                                  thresholds.motion,
                                  previous.motion)
        )
    }

    /// Sharpness and mean luma: pass by rising above `enter`, fail by falling
    /// below `exit`. Between them, hold.
    static func higherIsBetter(_ value: Double,
                               _ threshold: Threshold,
                               _ wasPassing: Bool) -> Bool {
        let enter = NSDecimalNumber(decimal: threshold.enter).doubleValue
        let exit = NSDecimalNumber(decimal: threshold.exit).doubleValue

        if value >= enter { return true }
        if value < exit { return false }
        return wasPassing
    }

    /// Clipping and motion: pass by falling below `enter`, fail by rising above
    /// `exit`. The band runs the other way because less is better.
    static func lowerIsBetter(_ value: Double,
                              _ threshold: Threshold,
                              _ wasPassing: Bool) -> Bool {
        let enter = NSDecimalNumber(decimal: threshold.enter).doubleValue
        let exit = NSDecimalNumber(decimal: threshold.exit).doubleValue

        if value <= enter { return true }
        if value > exit { return false }
        return wasPassing
    }
}

// MARK: - Phase transitions

private extension Gate {

    static func nextPhase(from phase: GatePhase,
                          verdicts: MetricVerdicts,
                          holdFrames: Int) -> GatePhase {
        guard verdicts.allPass else {
            // Any failing frame resets the run to zero, not down by one.
            return .blocked(reasons: verdicts.failures)
        }

        switch phase {
        case .armed:
            return .armed
        case .holding(let count, _):
            let next = count + 1
            return next >= holdFrames ? .armed : .holding(count: next, required: holdFrames)
        case .blocked, .fired:
            return holdFrames <= 1 ? .armed : .holding(count: 1, required: holdFrames)
        }
    }

    static func beginNextStep(after state: GateState,
                              stepCount: Int,
                              tick: Int) -> GateState {
        let next = state.stepIndex + 1
        guard next < stepCount else {
            return GateState(stepIndex: next,
                             phase: .fired,
                             verdicts: state.verdicts,
                             phaseChangedAt: tick,
                             isComplete: true)
        }

        // A new step starts with nothing measured: its region is different, so
        // the previous step's verdicts say nothing about it.
        return GateState(stepIndex: next,
                         phase: .blocked(reasons: Set(BlockReason.allCases)),
                         verdicts: .unmeasured,
                         phaseChangedAt: tick,
                         isComplete: false)
    }
}
