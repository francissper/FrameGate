//
//  ROIMapper.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 12/09/26.
//

import CoreGraphics

public enum ROIMapper {

    /// Maps a plan region into both the buffer space (where it is measured) and
    /// the view space (where it is drawn). These two rectangles must describe
    /// the same region or every measurement is meaningless.
    public static func map(
        _ region: NormalizedRegion,
        bufferSize: CGSize,
        sensorRotation: SensorRotation,
        mirrored: Bool,
        displayOrientation: DisplayOrientation,
        viewSize: CGSize,
        fillMode: FillMode
    ) -> MappedRegion {
        let normalized = CGRect(x: region.x, y: region.y,
                                width: region.width, height: region.height)

        // The buffer rect: the region as it sits in the sensor's own frame.
        let inBuffer = CGRect(x: normalized.minX * bufferSize.width,
                              y: normalized.minY * bufferSize.height,
                              width: normalized.width * bufferSize.width,
                              height: normalized.height * bufferSize.height)

        // The view rect: the same region after the sensor's rotation, the
        // mirroring, and the display's own rotation have been applied.
        let totalRotation = combine(sensorRotation, displayOrientation)
        var forView = NormalizedTransform.rotated(normalized, by: totalRotation)
        if mirrored {
            forView = NormalizedTransform.mirrored(forView)
        }

        let content = ViewFitting.contentRect(bufferSize: rotatedSize(bufferSize, by: totalRotation),
                                              viewSize: viewSize,
                                              fillMode: fillMode)
        let inView = CGRect(x: content.minX + forView.minX * content.width,
                            y: content.minY + forView.minY * content.height,
                            width: forView.width * content.width,
                            height: forView.height * content.height)

        return MappedRegion(buffer: inBuffer, view: inView)
    }

    private static func rotatedSize(_ size: CGSize, by rotation: SensorRotation) -> CGSize {
        switch rotation {
        case .deg0, .deg180: return size
        case .deg90, .deg270: return CGSize(width: size.height, height: size.width)
        }
    }

    /// The sensor's rotation and the display's own orientation compose into one.
    private static func combine(_ sensor: SensorRotation,
                                _ display: DisplayOrientation) -> SensorRotation {
        let displayDegrees: Int
        switch display {
        case .portrait: displayDegrees = 0
        case .landscapeLeft: displayDegrees = 90
        case .portraitUpsideDown: displayDegrees = 180
        case .landscapeRight: displayDegrees = 270
        }
        let total = (sensor.rawValue + displayDegrees) % 360
        return SensorRotation(rawValue: total) ?? .deg0
    }
}
