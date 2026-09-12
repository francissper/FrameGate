//
//  PlanParser+Date.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 12/09/26.
//

import Foundation

extension PlanParser {

  static func date(from raw: String?, into diagnostics: inout [Diagnostic]) -> Date {
      guard let raw else {
          diagnostics.append(Diagnostic(
              severity: .info,
              message: "createdAt is missing, using the epoch"
          ))
          return Date(timeIntervalSince1970: 0)
      }

      let strict = ISO8601DateFormatter()
      strict.formatOptions = [.withInternetDateTime]
      if let date = strict.date(from: raw) {
          return date
      }

      let zoneless = DateFormatter()
      zoneless.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
      zoneless.timeZone = TimeZone(secondsFromGMT: 0)
      zoneless.locale = Locale(identifier: "en_US_POSIX")
      if let date = zoneless.date(from: raw) {
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
