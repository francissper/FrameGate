//
//  ManifestEncoder.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 13/09/26.
//

import Foundation

/// Serializes a manifest to the wire format. Written by hand rather than through
/// `Codable` so the contract is visible in one place and cannot drift when a
/// property is added to the model.
public enum ManifestEncoder {

    /// Four places for every measured value: more precision than any threshold
    /// needs, and few enough to read at a glance.
    static let decimalPlaces = 4

    public static func encode(_ manifest: CaptureManifest) throws -> Data {
        let payload: [String: Any] = [
            "captureId": manifest.captureID.uuidString,
            "planId": manifest.planID,
            "planCreatedAt": timestamp(manifest.planCreatedAt),
            "stepId": manifest.stepID,
            "capturedAt": timestamp(manifest.capturedAt),
            "sensorRotation": manifest.sensorRotation.rawValue,
            "displayOrientation": label(manifest.displayOrientation),
            "mirrored": manifest.mirrored,
            "region": [
                "x": decimal(manifest.region.x),
                "y": decimal(manifest.region.y),
                "width": decimal(manifest.region.width),
                "height": decimal(manifest.region.height)
            ],
            "metrics": [
                "sharpness": decimal(manifest.metrics.sharpness),
                "meanLuma": decimal(manifest.metrics.meanLuma),
                "crushedFraction": decimal(manifest.metrics.crushedFraction),
                "blownFraction": decimal(manifest.metrics.blownFraction),
                "motion": decimal(manifest.metrics.motion)
            ],
            "holdFramesRequired": manifest.holdFramesRequired,
            "framesDropped": manifest.framesDropped
        ]

        return try JSONSerialization.data(withJSONObject: payload,
                                          options: [.sortedKeys])
    }
}

// MARK: - Formatters

private extension ManifestEncoder {

    /// ISO 8601 in UTC with milliseconds. No zone ambiguity, ever.
    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    static func decimal(_ value: Double) -> String {
        String(format: "%.\(decimalPlaces)f", value)
    }

    static func decimal(_ value: CGFloat) -> String {
        decimal(Double(value))
    }

    static func label(_ orientation: DisplayOrientation) -> String {
        switch orientation {
        case .portrait: return "portrait"
        case .portraitUpsideDown: return "portraitUpsideDown"
        case .landscapeLeft: return "landscapeLeft"
        case .landscapeRight: return "landscapeRight"
        }
    }
}
