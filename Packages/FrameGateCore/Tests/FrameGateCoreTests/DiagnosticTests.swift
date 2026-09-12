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
    let diagnostic = Diagnostic(severity: .warning, message: "threshold is missing")
    XCTAssertEqual(diagnostic.text, "[warning] threshold is missing")
  }
  
  func testTextIncludesStepIDWhenPresent() {
    let diagnostic = Diagnostic(severity: .info, stepID: "front-label", message: "holdframes coerced from string")
    XCTAssertEqual(diagnostic.text, "[info] step 'front-label': holdframes coerced from string")
  }
}
