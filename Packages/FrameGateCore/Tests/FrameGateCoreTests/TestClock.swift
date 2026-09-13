//
//  TestClock.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 13/09/26.
//

import Foundation
@testable import FrameGateCore

/// A clock the test moves by hand. Nothing ever waits.
final class TestClock: Clock, @unchecked Sendable {
    private var current: Date

    init(_ start: Date = Date(timeIntervalSince1970: 1_000_000)) {
        current = start
    }

    var now: Date { current }

    func advance(by seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
    }
}
