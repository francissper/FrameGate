//
//  GateState.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 13/09/26.
//

/// Which metric is keeping the shutter disabled. The HUD names these directly.
public enum BlockReason: String, Sendable, CaseIterable, Codable {
    case sharpness
    case underexposed
    case overexposed
    case motion
}

/// Where the gate is for the current step. The shutter is enabled in `armed` only.
public enum GatePhase: Equatable, Sendable {
    /// At least one metric is failing. Never empty: with nothing failing the
    /// phase is `holding` or `armed` instead.
    case blocked(reasons: Set<BlockReason>)
    /// Every metric passes, but the run is not long enough yet.
    case holding(count: Int, required: Int)
    /// The run is complete and the shutter is enabled.
    case armed
    /// The shutter was pressed for this step. Transient: the next frame moves on.
    case fired
}

public struct GateState: Equatable, Sendable {
    /// Index into the plan's steps.
    public let stepIndex: Int
    public let phase: GatePhase
    /// Carried between frames so a metric inside the hysteresis band keeps its
    /// last verdict rather than flipping.
    public let verdicts: MetricVerdicts
    /// The tick at which the phase last changed. Recorded rather than read from
    /// a clock, so the reducer stays pure.
    public let phaseChangedAt: Int
    public let isComplete: Bool

    public init(stepIndex: Int = 0,
                phase: GatePhase = .blocked(reasons: Set(BlockReason.allCases)),
                verdicts: MetricVerdicts = .unmeasured,
                phaseChangedAt: Int = 0,
                isComplete: Bool = false) {
        self.stepIndex = stepIndex
        self.phase = phase
        self.verdicts = verdicts
        self.phaseChangedAt = phaseChangedAt
        self.isComplete = isComplete
    }

    /// The metric the HUD names. Stable ordering so it does not flicker between
    /// equally-failing metrics.
    public var blockingReason: BlockReason? {
        guard case .blocked(let reasons) = phase else { return nil }
        return BlockReason.allCases.first { reasons.contains($0) }
    }
}
