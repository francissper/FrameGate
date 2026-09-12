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
    public let message: String

    public init(severity: Severity, message: String) {
        self.severity = severity
        self.message = message
    }

    public var text: String {
        "[\(severity.rawValue)] \(message)"
    }
}
