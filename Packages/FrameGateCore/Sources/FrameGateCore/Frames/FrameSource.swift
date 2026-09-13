//
//  FrameSource.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 12/09/26.
//

import Combine

/// The seam that lets the pipeline run without a camera. A real
/// AVCaptureSession would sit behind this same protocol.
public protocol FrameSource: AnyObject {
    /// Frames delivered on a background queue, keep-latest: when the consumer
    /// falls behind the newest frame wins and the rest are dropped.
    var frames: AnyPublisher<Frame, Never> { get }

    /// Frames dropped rather than queued. Surfaced in the HUD as evidence
    /// that backpressure is real.
    var droppedCount: AnyPublisher<Int, Never> { get }

    func start()
    func stop()
}
