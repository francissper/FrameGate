//
//  URLSessionUploadTransport.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 14/09/26.
//

import Foundation

/// The real transport: URLSession against the contract in the README, multipart
/// with a manifest part and a frame part, and an Idempotency-Key identical
/// across every retry of the same shot.
public final class URLSessionUploadTransport: UploadTransport, @unchecked Sendable {

    private let endpoint: URL
    private let session: URLSession

    public init(endpoint: URL, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    public func send(manifest: Data,
                     frame: Data,
                     idempotencyKey: UUID) async -> UploadOutcome {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(idempotencyKey.uuidString, forHTTPHeaderField: "Idempotency-Key")

        let boundary = "FrameGate-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.body(manifest: manifest, frame: frame, boundary: boundary)

        do {
            let (_, response) = try await session.data(for: request)
            return Self.outcome(for: response as? HTTPURLResponse)
        } catch {
            // The shot's fate is unknown. The unchanged idempotency key lets the
            // next attempt find out without duplicating the capture.
            return .timedOut
        }
    }
}

private extension URLSessionUploadTransport {

    static func body(manifest: Data, frame: Data, boundary: String) -> Data {
        var body = Data()

        func appendField(name: String, filename: String, contentType: String, data: Data) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data(
                "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8
            ))
            body.append(Data("Content-Type: \(contentType)\r\n\r\n".utf8))
            body.append(data)
            body.append(Data("\r\n".utf8))
        }

        appendField(name: "manifest", filename: "manifest.json",
                    contentType: "application/json", data: manifest)
        appendField(name: "frame", filename: "frame.jpg",
                    contentType: "image/jpeg", data: frame)
        body.append(Data("--\(boundary)--\r\n".utf8))

        return body
    }

    static func outcome(for response: HTTPURLResponse?) -> UploadOutcome {
        guard let response else { return .timedOut }

        switch response.statusCode {
        case 201:
            return .stored(duplicate: false)
        case 200:
            return .stored(duplicate: true)
        case 422:
            return .rejected
        case 500, 503:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
                .flatMap(TimeInterval.init)
            return .retryable(retryAfter: retryAfter)
        default:
            return .retryable(retryAfter: nil)
        }
    }
}
