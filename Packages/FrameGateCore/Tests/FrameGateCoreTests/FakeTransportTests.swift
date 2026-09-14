//
//  FakeTransportTests.swift
//  FrameGateCoreTests
//
//  Created by Franciss Peralta on 14/09/26.
//

import XCTest
@testable import FrameGateCore

final class FakeTransportTests: XCTestCase {

    private let manifest = Data("{}".utf8)
    private let frame = Data(repeating: 0xFF, count: 128)

    func testFailureScriptAppliesOnlyToFirstCapture() async {
        let transport = FakeTransport.suggestedScript
        let firstCaptureID = UUID()
        let secondCaptureID = UUID()

        let firstOutcome = await send(
            transport,
            captureID: firstCaptureID
        )

        XCTAssertEqual(
            firstOutcome,
            .retryable(retryAfter: nil)
        )

        let secondOutcome = await send(
            transport,
            captureID: secondCaptureID
        )

        XCTAssertEqual(
            secondOutcome,
            .stored(duplicate: false),
            "captures after the first must succeed immediately"
        )

        let secondRequest = transport.requests.last

        XCTAssertEqual(
            secondRequest?.idempotencyKey,
            secondCaptureID
        )

        XCTAssertEqual(
            secondRequest?.attempt,
            1
        )
    }

    func testFirstCaptureRunsTheWholeSuggestedScript() async {
        let transport = FakeTransport.suggestedScript
        let captureID = UUID()

        var outcomes: [UploadOutcome] = []

        for _ in 0..<5 {
            outcomes.append(
                await send(
                    transport,
                    captureID: captureID
                )
            )
        }

        XCTAssertEqual(
            outcomes,
            [
                .retryable(retryAfter: nil),
                .retryable(retryAfter: nil),
                .timedOut,
                .retryable(retryAfter: nil),
                .stored(duplicate: false)
            ]
        )

        XCTAssertEqual(
            transport.requests.map(\.attempt),
            [1, 2, 3, 4, 5]
        )

        XCTAssertEqual(
            Set(transport.requests.map(\.idempotencyKey)),
            [captureID]
        )
    }
}

// MARK: - Helpers

private extension FakeTransportTests {

    func send(
        _ transport: FakeTransport,
        captureID: UUID
    ) async -> UploadOutcome {
        await transport.send(
            manifest: manifest,
            frame: frame,
            idempotencyKey: captureID
        )
    }
}
