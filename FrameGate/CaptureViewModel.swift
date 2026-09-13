//
//  CaptureViewModel.swift
//  FrameGate
//
//  Created by Franciss Peralta on 13/09/26.
//

import Combine
import CoreGraphics
import Foundation
import FrameGateCore

struct CaptureScreenState: Equatable {
    var queueCount: Int = 0
    var stepText: String = "Step 1 of 1"
    var phaseText: String = "starting"
    var blockingText: String = "blocked by: -"
    var millisecondsText: String = "0.0 ms/frame"
    var droppedText: String = "0 dropped"
    var sharpnessText: String = "0.00"
    var sharpnessState: String = "wait"
    var exposureText: String = "0.00"
    var exposureState: String = "wait"
    var motionText: String = "0.00"
    var motionState: String = "wait"
    var outline: CGRect = .zero
    var goodFramesText: String = "0 / 8 good frames"
    var shutterText: String = "off"
    var shutterSubtitle: String = "shutter disabled"
    var isShutterEnabled = false
    var errorText: String?
}

enum CaptureEvent {
    case appeared
    case disappeared
    case geometryChanged(CGSize)
    case shutterTapped
}

enum CaptureEffect {
    case acceptedStep(String)
}

@MainActor
final class CaptureViewModel: ObservableObject {

    @Published private(set) var state: CaptureScreenState

    let effects = PassthroughSubject<CaptureEffect, Never>()

    private let plan: Plan
    private let pipeline: CapturePipeline?
    private var cancellables: Set<AnyCancellable> = []
    private var isRunning = false

    init() {
        switch Self.makePipeline() {
        case .success(let dependencies):
            plan = dependencies.plan
            pipeline = dependencies.pipeline
            state = CaptureScreenState(
                stepText: "Step 1 of \(dependencies.plan.steps.count)",
                goodFramesText: "0 / \(dependencies.plan.steps[0].holdFrames) good frames"
            )
            bindPipeline(dependencies.pipeline)

        case .failure(let error):
            let fallbackPlan = Self.fallbackPlan()
            plan = fallbackPlan
            pipeline = nil
            state = CaptureScreenState(
                phaseText: "unavailable",
                goodFramesText: "0 / \(fallbackPlan.steps[0].holdFrames) good frames",
                errorText: error.message
            )
        }
    }

    func send(_ event: CaptureEvent) {
        switch event {
        case .appeared:
            start()
        case .disappeared:
            stop()
        case .geometryChanged(let size):
            pipeline?.updateGeometry(viewSize: size,
                                     orientation: .portrait,
                                     fillMode: .aspectFit)
        case .shutterTapped:
            guard let step = pipeline?.fire() else { return }
            effects.send(.acceptedStep(step.id))
        }
    }
}

private extension CaptureViewModel {

    struct Dependencies {
        let plan: Plan
        let pipeline: CapturePipeline
    }

    struct SetupError: Error {
        let message: String
    }

    static func makePipeline() -> Result<Dependencies, SetupError> {
        let plan = fallbackPlan()
        let size = CGSize(width: 160, height: 120)
        let patterns: [PatternGenerator.Pattern] = [.sharp, .sharp, .sharp, .sharpLeftHalf]
        let buffers = patterns.compactMap { PatternGenerator.makeBuffer($0, size: size) }

        guard !buffers.isEmpty else {
            return .failure(SetupError(message: "replay frames unavailable"))
        }

        let source = ReplayFrameSource(buffers: buffers, frameRate: 60)
        let pipeline = CapturePipeline(source: source, plan: plan)
        return .success(Dependencies(plan: plan, pipeline: pipeline))
    }

    static func fallbackPlan() -> Plan {
        let thresholds = Thresholds(
            sharpness: Threshold(enter: 0.5, exit: 0.4),
            meanLuma: Threshold(enter: 0.1, exit: 0.05),
            clippedFraction: Threshold(enter: 0.5, exit: 0.6),
            motion: Threshold(enter: 0.5, exit: 0.6)
        )
        let step = Step(id: "front-label",
                        kind: .single,
                        label: "Front label",
                        roi: fullFrameRegion(),
                        thresholds: thresholds,
                        holdFrames: 8)
        return Plan(id: "simulator-replay", createdAt: Date(), steps: [step])
    }

    static func fullFrameRegion() -> NormalizedRegion {
        guard let region = NormalizedRegion(x: 0, y: 0, width: 1, height: 1) else {
            preconditionFailure("The full-frame normalized region should always be valid.")
        }
        return region
    }

    func bindPipeline(_ pipeline: CapturePipeline) {
        pipeline.ticks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tick in
                self?.apply(tick)
            }
            .store(in: &cancellables)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        pipeline?.start()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        pipeline?.stop()
    }

    func apply(_ tick: CaptureTick) {
        let stepIndex = min(tick.gate.stepIndex, max(plan.steps.count - 1, 0))
        let step = plan.steps[stepIndex]
        let holdProgress = holdProgress(for: tick.gate.phase, required: step.holdFrames)

        state.stepText = "Step \(stepIndex + 1) of \(plan.steps.count)"
        state.phaseText = phaseText(for: tick.gate.phase)
        state.blockingText = blockingText(for: tick.gate)
        state.millisecondsText = String(format: "%.1f ms/frame", tick.millisecondsPerFrame)
        state.droppedText = "\(tick.framesDropped) dropped"
        state.sharpnessText = String(format: "%.2f", tick.metrics.sharpness)
        state.sharpnessState = tick.gate.verdicts.sharpness ? "ok" : "fail"
        state.exposureText = String(format: "%.2f", tick.metrics.meanLuma)
        state.exposureState = tick.gate.verdicts.meanLuma && tick.gate.verdicts.clipping ? "ok" : "fail"
        state.motionText = String(format: "%.2f", tick.metrics.motion)
        state.motionState = tick.gate.verdicts.motion ? "ok" : "fail"
        state.outline = tick.outline
        state.goodFramesText = "\(holdProgress.current) / \(holdProgress.required) good frames"
        state.shutterText = tick.gate.phase == .armed ? "on" : "off"
        state.shutterSubtitle = tick.gate.phase == .armed ? "shutter enabled" : "shutter disabled"
        state.isShutterEnabled = tick.gate.phase == .armed
        state.errorText = nil
    }

    func phaseText(for phase: GatePhase) -> String {
        switch phase {
        case .blocked:
            return "blocked"
        case .holding:
            return "holding"
        case .armed:
            return "armed"
        case .fired:
            return "fired"
        }
    }

    func blockingText(for gate: GateState) -> String {
        guard let reason = gate.blockingReason else {
            return "blocked by: -"
        }
        return "blocked by: \(reason.rawValue)"
    }

    func holdProgress(for phase: GatePhase, required: Int) -> (current: Int, required: Int) {
        switch phase {
        case .holding(let count, let required):
            return (count, required)
        case .armed:
            return (required, required)
        default:
            return (0, required)
        }
    }
}
