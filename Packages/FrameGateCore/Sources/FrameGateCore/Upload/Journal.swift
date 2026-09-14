//
//  Journal.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 13/09/26.
//

import Foundation

public enum JournalError: Error {
    case encodingFailed
}

/// An append-only log of state transitions, one JSON object per line.
///
/// Append-only rather than a mutable store because a single `write` followed by
/// `synchronize` is either fully on disk or not there at all. Rewriting a record
/// in place can be interrupted halfway and leave a corrupt one; appending cannot.
/// A torn final line is discarded on replay and everything before it is intact.
public final class Journal {

    private let url: URL
    private let handle: FileHandle

    public init(url: URL) throws {
        self.url = url
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        self.handle = try FileHandle(forUpdating: url)
        _ = try handle.seekToEnd()
    }

    deinit {
        try? handle.close()
    }

    /// Appends one event and forces it to disk before returning. The caller can
    /// rely on the event having survived once this returns.
    public func append(_ event: JournalEvent) throws {
        let json = try serialize(event)
        guard let data = (json + "\n").data(using: .utf8) else { return }
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }

    /// Rebuilds the current records by replaying every event in order.
    public func replay() throws -> [CaptureRecord] {
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [] }
        guard let text = String(bytes: data, encoding: .utf8) else {
            // The whole file is not valid UTF-8: nothing here can be trusted.
            return []
        }

        var records: [UUID: CaptureRecord] = [:]
        var order: [UUID] = []

        for line in text.components(separatedBy: "\n") where !line.isEmpty {
            guard
                let lineData = line.data(using: .utf8),
                let json = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any],
                let event = deserialize(json)
            else { continue }
            apply(event, to: &records, order: &order)
        }

        return order.compactMap { records[$0] }
    }
}

// MARK: - Serialization

private extension Journal {

    func serialize(_ event: JournalEvent) throws -> String {
        let dict: [String: Any]
        switch event {
        case .captured(let id, let manifest, let frame, let at):
            dict = ["event": "captured",
                    "captureId": id.uuidString,
                    "manifestFilename": manifest,
                    "frameFilename": frame,
                    "at": at.timeIntervalSince1970]
        case .attempted(let id, let attempt, let at):
            dict = ["event": "attempted",
                    "captureId": id.uuidString,
                    "attempt": attempt,
                    "at": at.timeIntervalSince1970]
        case .retryScheduled(let id, let next, let at):
            dict = ["event": "retryScheduled",
                    "captureId": id.uuidString,
                    "nextAttemptAt": next.timeIntervalSince1970,
                    "at": at.timeIntervalSince1970]
        case .uploaded(let id, let at):
            dict = ["event": "uploaded",
                    "captureId": id.uuidString,
                    "at": at.timeIntervalSince1970]
        case .failed(let id, let at):
            dict = ["event": "failed",
                    "captureId": id.uuidString,
                    "at": at.timeIntervalSince1970]
        case .manuallyRetried(let id, let at):
            dict = ["event": "manuallyRetried",
                    "captureId": id.uuidString,
                    "at": at.timeIntervalSince1970]
        }
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        guard let json = String(bytes: data, encoding: .utf8) else {
            throw JournalError.encodingFailed
        }
        return json
    }

    func filename(from value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        return URL(fileURLWithPath: raw).lastPathComponent
    }

    func deserialize(_ json: [String: Any]) -> JournalEvent? {
        guard
            let eventType = json["event"] as? String,
            let idString = json["captureId"] as? String,
            let id = UUID(uuidString: idString),
            let atRaw = json["at"] as? Double
        else { return nil }

        let at = Date(timeIntervalSince1970: atRaw)

        switch eventType {
        case "captured":
            guard let manifest = filename(from: json["manifestFilename"] ?? json["manifestPath"]),
                  let frame = filename(from: json["frameFilename"] ?? json["framePath"])
            else { return nil }
            return .captured(captureID: id, manifestFilename: manifest, frameFilename: frame, at: at)
        case "attempted":
            guard let attempt = json["attempt"] as? Int else { return nil }
            return .attempted(captureID: id, attempt: attempt, at: at)
        case "retryScheduled":
            guard let nextRaw = json["nextAttemptAt"] as? Double else { return nil }
            return .retryScheduled(captureID: id,
                                   nextAttemptAt: Date(timeIntervalSince1970: nextRaw),
                                   at: at)
        case "uploaded":
            return .uploaded(captureID: id, at: at)
        case "failed":
            return .failed(captureID: id, at: at)
        case "manuallyRetried":
            return .manuallyRetried(captureID: id, at: at)
        default:
            return nil
        }
    }
}

// MARK: - Reduction

private extension Journal {

    func apply(_ event: JournalEvent,
               to records: inout [UUID: CaptureRecord],
               order: inout [UUID]) {
        switch event {
        case .captured(let id, let manifest, let frame, _):
            records[id] = CaptureRecord(captureID: id,
                                        manifestFilename: manifest,
                                        frameFilename: frame)
            order.append(id)
        case .attempted(let id, let attempt, _):
            records[id]?.attempts = attempt
        case .retryScheduled(let id, let next, _):
            records[id]?.nextAttemptAt = next
        case .uploaded(let id, _):
            records[id]?.status = .uploaded
            records[id]?.nextAttemptAt = nil
        case .failed(let id, _):
            records[id]?.status = .failed
            records[id]?.nextAttemptAt = nil
        case .manuallyRetried(let id, _):
            records[id]?.status = .pending
            records[id]?.attempts = 0
            records[id]?.nextAttemptAt = nil
        }
    }
}
