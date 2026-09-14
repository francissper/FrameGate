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

/// Everything needed to persist an accepted shot.
///
/// The source `CVPixelBuffer` never escapes its frame-delivery callback. JPEG
/// encoding happens only for an accepted capture request, before that callback
/// returns, and the durable value that crosses the boundary is `Data`.
public struct CapturedShot: Sendable {
  public let step: Step
  public let frameData: Data
  public let sensorRotation: SensorRotation
  public let mirrored: Bool
  public let displayOrientation: DisplayOrientation
  public let metrics: FrameMetrics
  public let framesDropped: Int
}

/// Joins the frame source, the mapper, the analyzer and the gate.
///
/// This lives in Core rather than in a view model so the whole pipeline can be
/// driven by the replay source in a test, with no UI involved — and so a view
/// never holds a reference to the capture session or does any pixel maths.
public final class CapturePipeline: @unchecked Sendable {

  private struct ProcessingOutput {
    let tick: CaptureTick
    let shot: CapturedShot?
  }

  private let source: FrameSource
  private let analyzer: LumaAnalyzer
  private let plan: Plan

  private let tickSubject = PassthroughSubject<CaptureTick, Never>()
  private let shotSubject = PassthroughSubject<CapturedShot, Never>()
  private var cancellables: Set<AnyCancellable> = []

  /// All mutable pipeline state is confined to this queue. Frame processing
  /// enters it synchronously, so the source buffer cannot outlive delivery.
  private let stateQueue = DispatchQueue(
    label: "framegate.capture-pipeline",
    qos: .userInitiated
  )

  private var gate = GateState()
  private var frameCount = 0
  private var averageMilliseconds: Double = 0
  private var captureRequested = false

  /// Dropped-frame notifications arrive on the producer queue. Keep this lock
  /// tiny so reporting them never blocks frame production on pipeline work.
  private let droppedLock = NSLock()
  private var droppedCount = 0

  /// Geometry the view reports as it changes. The pipeline cannot know these.
  private var viewSize: CGSize = .zero
  private var displayOrientation: DisplayOrientation = .portrait
  private var fillMode: FillMode = .aspectFill

  public init(
    source: FrameSource,
    analyzer: LumaAnalyzer = LumaAnalyzer(),
    plan: Plan
  ) {
    self.source = source
    self.analyzer = analyzer
    self.plan = plan
  }

  public var ticks: AnyPublisher<CaptureTick, Never> {
    tickSubject.eraseToAnyPublisher()
  }

  /// Accepted captures. The payload contains JPEG data, never a pixel buffer.
  public var shots: AnyPublisher<CapturedShot, Never> {
    shotSubject.eraseToAnyPublisher()
  }

  public func start() {
    source.frames
      .sink { [weak self] frame in
        self?.process(frame)
      }
      .store(in: &cancellables)

    source.droppedCount
      .sink { [weak self] count in
        self?.setDroppedCount(count)
      }
      .store(in: &cancellables)

    source.start()
  }

  public func stop() {
    source.stop()
    cancellables.removeAll()

    stateQueue.sync {
      captureRequested = false
    }
  }

  /// Called from the view as geometry changes. Values, not a reference back.
  public func updateGeometry(
    viewSize: CGSize,
    orientation: DisplayOrientation,
    fillMode: FillMode
  ) {
    stateQueue.sync {
      self.viewSize = viewSize
      self.displayOrientation = orientation
      self.fillMode = fillMode
    }
  }

  /// Requests a capture for the next frame that still satisfies the armed gate.
  /// The frame itself is never retained while waiting for the request.
  @discardableResult
  public func requestFire() -> Bool {
    stateQueue.sync {
      guard gate.phase == .armed,
            !gate.isComplete,
            gate.stepIndex < plan.steps.count,
            !captureRequested
      else {
        return false
      }

      captureRequested = true
      return true
    }
  }
}

// MARK: - Frame processing

private extension CapturePipeline {

  func process(_ frame: Frame) {
    let output = stateQueue.sync {
      processSynchronized(frame)
    }

    guard let output else {
      return
    }

    tickSubject.send(output.tick)

    if let shot = output.shot {
      shotSubject.send(shot)
    }
  }

  private func processSynchronized(_ frame: Frame) -> ProcessingOutput? {
    guard gate.stepIndex < plan.steps.count else {
      return nil
    }

    let step = plan.steps[gate.stepIndex]
    let startedAt = CFAbsoluteTimeGetCurrent()

    let mapped = ROIMapper.map(
      step.roi,
      bufferSize: frame.size,
      sensorRotation: frame.sensorRotation,
      mirrored: frame.mirrored,
      displayOrientation: displayOrientation,
      viewSize: viewSize,
      fillMode: fillMode
    )

    guard let metrics = analyzer.analyze(
      frame.buffer,
      region: mapped.buffer
    ) else {
      return nil
    }

    frameCount += 1

    var nextGate = Gate.advance(
      gate,
      metrics: metrics,
      thresholds: step.thresholds,
      holdFrames: step.holdFrames,
      stepCount: plan.steps.count,
      tick: frameCount
    )

    let dropped = currentDroppedCount()
    var capturedShot: CapturedShot?

    if captureRequested {
      captureRequested = false

      if nextGate.phase == .armed,
         let frameData = JPEGEncoder.encode(frame.buffer) {
        nextGate = Gate.fire(
          nextGate,
          tick: frameCount
        )

        analyzer.reset()

        capturedShot = CapturedShot(
          step: step,
          frameData: frameData,
          sensorRotation: frame.sensorRotation,
          mirrored: frame.mirrored,
          displayOrientation: displayOrientation,
          metrics: metrics,
          framesDropped: dropped
        )
      }
    }

    gate = nextGate

    let elapsed = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000

    averageMilliseconds = averageMilliseconds == 0
    ? elapsed
    : averageMilliseconds * 0.9 + elapsed * 0.1

    let tick = CaptureTick(
      gate: gate,
      metrics: metrics,
      outline: mapped.view,
      millisecondsPerFrame: averageMilliseconds,
      framesDropped: dropped
    )

    return ProcessingOutput(
      tick: tick,
      shot: capturedShot
    )
  }

  func setDroppedCount(_ count: Int) {
    droppedLock.lock()
    droppedCount = count
    droppedLock.unlock()
  }

  func currentDroppedCount() -> Int {
    droppedLock.lock()
    defer {
      droppedLock.unlock()
    }
    return droppedCount
  }
}
