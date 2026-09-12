//
//  LenientContainer.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 12/09/26.
//

import Foundation

/// Wraps a keyed container and matches keys case-insensitively, recording every
/// key it never looked at so unknown ones can be reported.
struct LenientContainer {
    private let container: KeyedDecodingContainer<AnyCodingKey>
    private var consumed: Set<String> = []

    init(_ container: KeyedDecodingContainer<AnyCodingKey>) {
        self.container = container
    }

    private mutating func key(for name: String) -> AnyCodingKey? {
        let target = name.lowercased()
        let matches = container.allKeys.filter { $0.stringValue.lowercased() == target }
        guard let first = matches.first else { return nil }
        consumed.formUnion(matches.map(\.stringValue))
        return first
    }

    /// Keys present in the payload that were never requested.
    var unusedKeys: [String] {
        container.allKeys.map(\.stringValue).filter { !consumed.contains($0) }
    }

    mutating func decodeIfPresent<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let key = key(for: name) else { return nil }
        return try? container.decodeIfPresent(type, forKey: key)
    }

    mutating func contains(_ name: String) -> Bool {
        key(for: name) != nil
    }

    mutating func nested(_ name: String) -> LenientContainer? {
        guard let key = key(for: name),
              let nested = try? container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: key)
        else { return nil }
        return LenientContainer(nested)
    }
}
