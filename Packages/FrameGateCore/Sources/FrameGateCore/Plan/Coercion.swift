//
//  Coercion.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 12/09/26.
//

import Foundation

enum Coercion {
    /// Accepts a JSON number, or a string that is unambiguously an integer.
    /// Returns the value and whether it had to be coerced.
    static func integer(_ container: inout LenientContainer, _ name: String) -> (value: Int, coerced: Bool)? {
        if let direct = container.decodeIfPresent(Int.self, name) {
            return (direct, false)
        }
        guard let text = container.decodeIfPresent(String.self, name),
              text == text.trimmingCharacters(in: .whitespaces),
              let value = Int(text)
        else { return nil }
        return (value, true)
    }

    /// Thresholds travel as strings and are parsed digit by digit, never via Double.
    static func decimal(_ container: inout LenientContainer, _ name: String) -> Decimal? {
        guard let text = container.decodeIfPresent(String.self, name) else { return nil }
        return Decimal(string: text)
    }
}
