//
//  ReplayFrameSourceTests.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 12/09/26.
//

import XCTest
import Combine
import CoreVideo
@testable import FrameGateCore

final class ReplayFrameSourceTests: XCTestCase {

  private var cancellables: Set<AnyCancellable> = []

  override func tearDown() {
    cancellables.removeAll()
    super.tearDown()
  }

  private func makeSource(frameRate: Double = 60) throws -> ReplayFrameSource {
    let size = CGSize(width: 160, height: 120)
    let buffers = try PatternGenerator.Pattern.allCases.map {
      try XCTUnwrap(PatternGenerator.makeBuffer($0, size: size))
    }
    return ReplayFrameSource(buffers: buffers, frameRate: frameRate)
  }
}

// MARK: - Brief requirements

extension ReplayFrameSourceTests {

  func testFramesArriveOffTheMainThread() throws {
    let source = try makeSource()
    let arrived = expectation(description: "a frame arrived")
    var sawMainThread = false

    source.frames
      .prefix(5)
      .sink(receiveCompletion: { _ in
        arrived.fulfill()
      }, receiveValue: { _ in
        if Thread.isMainThread { sawMainThread = true }
      })
      .store(in: &cancellables)

    source.start()
    wait(for: [arrived], timeout: 2)
    source.stop()

    XCTAssertFalse(sawMainThread, "frame delivery must stay off the main thread")
  }

  func testFramesCarryTimestampAndGeometry() throws {
    let source = try makeSource()
    let received = expectation(description: "frames received")
    var frames: [Frame] = []

    source.frames
      .prefix(3)
      .sink(receiveCompletion: { _ in
        received.fulfill()
      }, receiveValue: { frames.append($0) })
      .store(in: &cancellables)

    source.start()
    wait(for: [received], timeout: 2)
    source.stop()

    XCTAssertEqual(frames.count, 3)
    XCTAssertEqual(frames[0].size, CGSize(width: 160, height: 120))
    XCTAssertEqual(frames[0].sensorRotation, .deg90)

    // Timestamps advance and are relative to start, not wall clock.
    XCTAssertLessThan(frames[0].timestamp, frames[2].timestamp)
    XCTAssertLessThan(frames[0].timestamp, 1)
  }

  func testTheSequenceCyclesThroughEveryBuffer() throws {
    let source = try makeSource()
    let received = expectation(description: "a full cycle")
    var sizes: [Int] = []

    source.frames
      .prefix(PatternGenerator.Pattern.allCases.count)
      .sink(receiveCompletion: { _ in
        received.fulfill()
      }, receiveValue: { frame in
        sizes.append(CVPixelBufferGetWidth(frame.buffer))
      })
      .store(in: &cancellables)

    source.start()
    wait(for: [received], timeout: 2)
    source.stop()

    XCTAssertEqual(sizes.count, PatternGenerator.Pattern.allCases.count)
  }
}

// MARK: - Backpressure

extension ReplayFrameSourceTests {

  func testASlowConsumerCausesDropsRatherThanAGrowingQueue() throws {
    // Produce far faster than the consumer can handle.
    let source = try makeSource(frameRate: 200)
    let finished = expectation(description: "consumer done")
    var delivered = 0
    var lastDropped = 0

    source.droppedCount
      .sink { lastDropped = $0 }
      .store(in: &cancellables)

    source.frames
      .prefix(10)
      .sink(receiveCompletion: { _ in
        finished.fulfill()
      }, receiveValue: { _ in
        Thread.sleep(forTimeInterval: 0.02)
        delivered += 1
      })
      .store(in: &cancellables)

    source.start()
    wait(for: [finished], timeout: 5)
    source.stop()

    XCTAssertEqual(delivered, 10)
    XCTAssertGreaterThan(lastDropped, 0,
                         "a consumer slower than the producer must cause drops")
  }

  func testStopHaltsDelivery() throws {
    let source = try makeSource()
    var received = 0

    source.frames
      .sink { _ in received += 1 }
      .store(in: &cancellables)

    source.start()
    Thread.sleep(forTimeInterval: 0.2)
    source.stop()

    let afterStop = received
    Thread.sleep(forTimeInterval: 0.2)

    XCTAssertEqual(received, afterStop, "no frames after stop")
    XCTAssertGreaterThan(afterStop, 0, "frames did arrive before stop")
  }
}
