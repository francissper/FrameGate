//
//  ReplayFrameSource.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 12/09/26.
//

import Combine
import CoreVideo
import Foundation
import os

/// Replays a pre-built sequence of buffers at a fixed rate on a background
/// queue. When the consumer falls behind the newest frame overwrites the slot
/// and the previous one is counted as dropped — there is no queue to grow, so
/// latency never accumulates the way it would on a real capture session.
public final class ReplayFrameSource: FrameSource, @unchecked Sendable {

  private let buffers: [CVPixelBuffer]
  private let interval: TimeInterval
  private let sensorRotation: SensorRotation
  private let mirrored: Bool

  private let queue = DispatchQueue(label: "framegate.frame-source", qos: .userInitiated)
  private let frameSubject = PassthroughSubject<Frame, Never>()
  private let droppedSubject = CurrentValueSubject<Int, Never>(0)

  private let deliveryQueue = DispatchQueue(label: "framegate.frame-delivery", qos: .userInitiated)
  private var lock = os_unfair_lock()
  private var pending: Frame?
  private var dropped = 0
  private var delivering = false

  private var timer: DispatchSourceTimer?
  private var index = 0
  private var startedAt: TimeInterval = 0

  public init(buffers: [CVPixelBuffer],
              frameRate: Double = 30,
              sensorRotation: SensorRotation = .deg90,
              mirrored: Bool = false) {
    self.buffers = buffers
    self.interval = 1 / max(frameRate, 1)
    self.sensorRotation = sensorRotation
    self.mirrored = mirrored
  }

  public var frames: AnyPublisher<Frame, Never> {
    frameSubject.eraseToAnyPublisher()
  }

  public var droppedCount: AnyPublisher<Int, Never> {
    droppedSubject.eraseToAnyPublisher()
  }
}

// MARK: - Lifecycle

extension ReplayFrameSource {

  public func start() {
    guard timer == nil, !buffers.isEmpty else { return }

    startedAt = Date().timeIntervalSince1970
    let source = DispatchSource.makeTimerSource(queue: queue)
    source.schedule(deadline: .now(), repeating: interval)
    source.setEventHandler { [weak self] in self?.produce() }
    timer = source
    source.resume()
  }

  public func stop() {
    timer?.cancel()
    timer = nil
    clearPending()
  }
}

// MARK: - Keep-latest

private extension ReplayFrameSource {

  /// Called on the producer's timer. Writes into the slot and counts whatever
  /// the consumer never got to.
  func produce() {
    let buffer = buffers[index % buffers.count]
    index += 1

    let frame = Frame(
      buffer: buffer,
      timestamp: Date().timeIntervalSince1970 - startedAt,
      size: CGSize(width: CVPixelBufferGetWidth(buffer),
                   height: CVPixelBufferGetHeight(buffer)),
      sensorRotation: sensorRotation,
      mirrored: mirrored
    )

    os_unfair_lock_lock(&lock)
    if pending != nil {
      // The consumer is still busy with an earlier frame. Overwrite the
      // slot rather than queueing: latency must not accumulate.
      dropped += 1
    }
    pending = frame
    let shouldDeliver = !delivering
    if shouldDeliver { delivering = true }
    let droppedNow = dropped
    os_unfair_lock_unlock(&lock)

    droppedSubject.send(droppedNow)

    if shouldDeliver {
      deliveryQueue.async { [weak self] in self?.drainSlot() }
    }
  }

  /// Runs on the delivery queue. Publishes whatever is in the slot, then checks
  /// again — a frame that arrived mid-delivery is picked up without a queue.
  func drainSlot() {
    while true {
      os_unfair_lock_lock(&lock)
      let frame = pending
      pending = nil
      if frame == nil { delivering = false }
      os_unfair_lock_unlock(&lock)

      guard let frame else { return }
      frameSubject.send(frame)
    }
  }

  func clearPending() {
    os_unfair_lock_lock(&lock)
    pending = nil
    delivering = false
    os_unfair_lock_unlock(&lock)
  }
}
