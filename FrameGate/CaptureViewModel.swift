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
}

enum CaptureEvent {
    case appeared
    case disappeared
    case geometryChanged(CGSize)
    case shutterTapped
}

@MainActor
final class CaptureViewModel: ObservableObject {

    @Published private(set) var state: CaptureScreenState

    private let container: AppContainer
    private var cancellables: Set<AnyCancellable> = []
    private var isRunning = false

    init(container: AppContainer) {
        self.container = container
        state = CaptureScreenState(
            stepText: "Step 1 of \(container.plan.steps.count)",
            goodFramesText: "0 / \(container.plan.steps[0].holdFrames) good frames"
        )
        bindPipeline(container.pipeline)
        bindQueueCount(container.queue)
    }

    func send(_ event: CaptureEvent) {
        switch event {
        case .appeared:
            start()
        case .disappeared:
            stop()
        case .geometryChanged(let size):
            container.pipeline.updateGeometry(viewSize: size,
                                              orientation: .portrait,
                                              fillMode: .aspectFit)
        case .shutterTapped:
            guard let shot = container.pipeline.fire() else { return }
            Task { await container.enqueue(shot) }
        }
    }
}

private extension CaptureViewModel {

    func bindPipeline(_ pipeline: CapturePipeline) {
        pipeline.ticks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tick in self?.apply(tick) }
            .store(in: &cancellables)
    }

    func bindQueueCount(_ queue: UploadQueue) {
        queue.state
            .receive(on: DispatchQueue.main)
            .map(\.count)
            .sink { [weak self] count in self?.state.queueCount = count }
            .store(in: &cancellables)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        container.pipeline.start()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        container.pipeline.stop()
    }

    func apply(_ tick: CaptureTick) {
        let stepIndex = min(tick.gate.stepIndex, max(container.plan.steps.count - 1, 0))
        let step = container.plan.steps[stepIndex]
        let holdProgress = holdProgress(for: tick.gate.phase, required: step.holdFrames)

        state.stepText = "Step \(stepIndex + 1) of \(container.plan.steps.count)"
        state.phaseText = phaseText(for: tick.gate)
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
        let isShutterEnabled = tick.gate.phase == .armed && !tick.gate.isComplete
        state.shutterText = isShutterEnabled ? "on" : "off"
        state.shutterSubtitle = isShutterEnabled ? "shutter enabled" : "shutter disabled"
        state.isShutterEnabled = isShutterEnabled
    }

    func phaseText(for gate: GateState) -> String {
        if gate.isComplete { return "complete" }

        switch gate.phase {
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
