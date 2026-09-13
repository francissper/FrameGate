//
//  CapturePipeline.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 13/09/26.
//

import Combine
import CoreGraphics
import Foundation

/// What one frame produced, ready for the HUD to render.
public struct CaptureTick: Equatable, Sendable {
    public let gate: GateState
    public let metrics: FrameMetrics
    /// The outline, in view coordinates. Drawn from here and nowhere else.
    public let outline: CGRect
    /// Rolling average, so the number does not jump every frame.
    public let millisecondsPerFrame: Double
    public let framesDropped: Int
}

/// Joins the frame source, the mapper, the analyzer and the gate.
///
/// This lives in Core rather than in a view model so the whole pipeline can be
/// driven by the replay source in a test, with no UI involved — and so a view
/// never holds a reference to the capture session or does any pixel maths.
public final class CapturePipeline: @unchecked Sendable {

    private let source: FrameSource
    private let analyzer: LumaAnalyzer
    private let plan: Plan

    private let tickSubject = PassthroughSubject<CaptureTick, Never>()
    private var cancellables: Set<AnyCancellable> = []

    private var gate = GateState()
    private var frameCount = 0
    private var droppedCount = 0
    private var averageMilliseconds: Double = 0

    /// Geometry the view reports as it changes. The pipeline cannot know these.
    private var viewSize: CGSize = .zero
    private var displayOrientation: DisplayOrientation = .portrait
    private var fillMode: FillMode = .aspectFill

    public init(source: FrameSource, analyzer: LumaAnalyzer = LumaAnalyzer(), plan: Plan) {
        self.source = source
        self.analyzer = analyzer
        self.plan = plan
    }

    public var ticks: AnyPublisher<CaptureTick, Never> {
        tickSubject.eraseToAnyPublisher()
    }

    public func start() {
        source.frames
            .sink { [weak self] frame in self?.process(frame) }
            .store(in: &cancellables)

        source.droppedCount
            .sink { [weak self] count in self?.droppedCount = count }
            .store(in: &cancellables)

        source.start()
    }

    public func stop() {
        source.stop()
        cancellables.removeAll()
    }

    /// Called from the view as geometry changes. Values, not a reference back.
    public func updateGeometry(viewSize: CGSize,
                               orientation: DisplayOrientation,
                               fillMode: FillMode) {
        self.viewSize = viewSize
        self.displayOrientation = orientation
        self.fillMode = fillMode
    }

    /// The shutter. Only meaningful while armed.
    public func fire() -> Step? {
        guard gate.phase == .armed, gate.stepIndex < plan.steps.count else { return nil }
        let step = plan.steps[gate.stepIndex]
        gate = Gate.fire(gate, tick: frameCount)
        // The analyzer's previous downsample belongs to this step's region.
        analyzer.reset()
        return step
    }
}

// MARK: - Frame processing

private extension CapturePipeline {

    func process(_ frame: Frame) {
        guard gate.stepIndex < plan.steps.count else { return }
        let step = plan.steps[gate.stepIndex]
        let startedAt = CFAbsoluteTimeGetCurrent()

        let mapped = ROIMapper.map(step.roi,
                                   bufferSize: frame.size,
                                   sensorRotation: frame.sensorRotation,
                                   mirrored: frame.mirrored,
                                   displayOrientation: displayOrientation,
                                   viewSize: viewSize,
                                   fillMode: fillMode)

        guard let metrics = analyzer.analyze(frame.buffer, region: mapped.buffer) else {
            return
        }

        frameCount += 1
        gate = Gate.advance(gate,
                            metrics: metrics,
                            thresholds: step.thresholds,
                            holdFrames: step.holdFrames,
                            stepCount: plan.steps.count,
                            tick: frameCount)

        let elapsed = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        // Exponential moving average: a rolling figure, not a spiky one.
        averageMilliseconds = averageMilliseconds == 0
            ? elapsed
            : averageMilliseconds * 0.9 + elapsed * 0.1

        tickSubject.send(CaptureTick(gate: gate,
                                     metrics: metrics,
                                     outline: mapped.view,
                                     millisecondsPerFrame: averageMilliseconds,
                                     framesDropped: droppedCount))
    }
}
