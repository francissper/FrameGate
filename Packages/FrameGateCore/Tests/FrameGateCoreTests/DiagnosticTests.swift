//
//  DiagnosticTests.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 11/09/26.
//

import XCTest
@testable import FrameGateCore

final class DiagnosticTests: XCTestCase {
    func testTextCarriesSeverityAndMessage() {
        let diagnostic = Diagnostic(severity: .warning, message: "umbral ausente")
        XCTAssertEqual(diagnostic.text, "[warning] umbral ausente")
    }
}
