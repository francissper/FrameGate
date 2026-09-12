//
//  PlanParser+Date.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 12/09/26.
//

import Foundation

extension PlanParser {

    private static let strictFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let zonelessFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static func date(from raw: String?, into diagnostics: inout [Diagnostic]) -> Date {
        guard let raw else {
            diagnostics.append(Diagnostic(
                severity: .info,
                message: "createdAt is missing, using the epoch"
            ))
            return Date(timeIntervalSince1970: 0)
        }

        if let date = strictFormatter.date(from: raw) {
            return date
        }

        if let date = zonelessFormatter.date(from: raw) {
            diagnostics.append(Diagnostic(
                severity: .info,
                message: "createdAt carries no timezone, read as UTC"
            ))
            return date
        }

        diagnostics.append(Diagnostic(
            severity: .info,
            message: "createdAt is unreadable, using the epoch"
        ))
        return Date(timeIntervalSince1970: 0)
    }
}
