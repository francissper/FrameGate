//
//  CapturePipelineTests.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 13/09/26.
//

import Combine
import CoreGraphics
import XCTest
@testable import FrameGateCore

final class CapturePipelineTests: XCTestCase {

  private var cancellables: Set<AnyCancellable> = []

  override func tearDown() {
    cancellables.removeAll()
    super.tearDown()
  }

  private func makePlan(holdFrames: Int = 3) throws -> Plan {
    let region = try XCTUnwrap(NormalizedRegion(x: 0, y: 0, width: 1, height: 1))
    let thresholds = Thresholds(
      sharpness: Threshold(enter: 0.5, exit: 0.4),
      meanLuma: Threshold(enter: 0.1, exit: 0.05),
      clippedFraction: Threshold(enter: 0.5, exit: 0.6),
      motion: Threshold(enter: 0.5, exit: 0.6)
    )
    let step = Step(id: "only-step", kind: .single, label: "Only step",
                    roi: region, thresholds: thresholds, holdFrames: holdFrames)
    return Plan(id: "test-plan", createdAt: Date(), steps: [step])
  }

  private func makeSource() throws -> ReplayFrameSource {
    let size = CGSize(width: 160, height: 120)
    let sharp = try XCTUnwrap(PatternGenerator.makeBuffer(.sharp, size: size))
    return ReplayFrameSource(buffers: [sharp], frameRate: 60)
  }
}

// MARK: - Arming

extension CapturePipelineTests {

  func testASteadySharpFeedArmsAfterTheRequiredRun() throws {
    let pipeline = CapturePipeline(source: try makeSource(), plan: try makePlan(holdFrames: 3))
    pipeline.updateGeometry(viewSize: CGSize(width: 390, height: 844),
                            orientation: .portrait, fillMode: .aspectFit)

    let armed = expectation(description: "armed")
    pipeline.ticks
      .filter { $0.gate.phase == .armed }
      .prefix(1)
      .sink { _ in armed.fulfill() }
      .store(in: &cancellables)

    pipeline.start()
    wait(for: [armed], timeout: 2)
    pipeline.stop()
  }

  func testTheOutlineIsNonEmptyOnceGeometryIsKnown() throws {
    let pipeline = CapturePipeline(source: try makeSource(), plan: try makePlan())
    pipeline.updateGeometry(viewSize: CGSize(width: 390, height: 844),
                            orientation: .portrait, fillMode: .aspectFit)

    let received = expectation(description: "a tick arrived")
    var outline: CGRect = .zero

    pipeline.ticks
      .prefix(1)
      .sink { tick in
        outline = tick.outline
        received.fulfill()
      }
      .store(in: &cancellables)

    pipeline.start()
    wait(for: [received], timeout: 2)
    pipeline.stop()

    XCTAssertGreaterThan(outline.width, 0, "geometry was known before the first frame")
  }
}

// MARK: - Firing

extension CapturePipelineTests {

  func testRequestingFireWhileArmedEmitsEncodedShot() throws {
    let pipeline = CapturePipeline(
      source: try makeSource(),
      plan: try makePlan(holdFrames: 2)
    )

    pipeline.updateGeometry(
      viewSize: CGSize(width: 390, height: 844),
      orientation: .portrait,
      fillMode: .aspectFit
    )

    let armed = expectation(description: "armed")

    pipeline.ticks
      .filter { $0.gate.phase == .armed }
      .prefix(1)
      .sink { _ in
        armed.fulfill()
      }
      .store(in: &cancellables)

    let captured = expectation(description: "captured")
    var shot: CapturedShot?

    pipeline.shots
      .prefix(1)
      .sink { value in
        shot = value
        captured.fulfill()
      }
      .store(in: &cancellables)

    pipeline.start()

    wait(
      for: [armed],
      timeout: 2
    )

    XCTAssertTrue(pipeline.requestFire())

    wait(
      for: [captured],
      timeout: 2
    )

    pipeline.stop()

    let unwrappedShot = try XCTUnwrap(shot)

    XCTAssertEqual(
      unwrappedShot.step.id,
      "only-step"
    )

    XCTAssertFalse(
      unwrappedShot.frameData.isEmpty
    )
  }

  func testRequestingFireWhileNotArmedReturnsFalse() throws {
    let pipeline = CapturePipeline(
      source: try makeSource(),
      plan: try makePlan()
    )

    XCTAssertFalse(
      pipeline.requestFire(),
      "nothing has run yet, the gate cannot be armed"
    )
  }
}

// MARK: - Reporting

extension CapturePipelineTests {

  func testPerformanceFiguresAreReportedOnEveryTick() throws {
    let pipeline = CapturePipeline(source: try makeSource(), plan: try makePlan())
    pipeline.updateGeometry(viewSize: CGSize(width: 390, height: 844),
                            orientation: .portrait, fillMode: .aspectFit)

    let received = expectation(description: "a tick arrived")
    var tick: CaptureTick?

    pipeline.ticks
      .prefix(1)
      .sink { value in
        tick = value
        received.fulfill()
      }
      .store(in: &cancellables)

    pipeline.start()
    wait(for: [received], timeout: 2)
    pipeline.stop()

    let unwrappedTick = try XCTUnwrap(tick)
    XCTAssertGreaterThanOrEqual(unwrappedTick.millisecondsPerFrame, 0)
    XCTAssertGreaterThanOrEqual(unwrappedTick.framesDropped, 0)
  }
}
