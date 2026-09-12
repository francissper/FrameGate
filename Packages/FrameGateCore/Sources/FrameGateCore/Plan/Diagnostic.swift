//
//  Diagnostic.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 11/09/26.
//

public struct Diagnostic: Equatable, Sendable {
  public enum Severity: String, Sendable {
    case info
    case warning
  }

  public let severity: Severity
  public let stepID: String?
  public let message: String

  public init(severity: Severity, stepID: String? = nil, message: String) {
    self.severity = severity
    self.stepID = stepID
    self.message = message
  }

  public var text: String {
    guard let stepID else { return "[\(severity.rawValue)] \(message)" }
    return "[\(severity.rawValue)] step '\(stepID)': \(message)"
  }
}
