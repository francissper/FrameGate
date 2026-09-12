//
//  Frame.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 12/09/26.
//

import CoreVideo
import CoreGraphics

/// One frame from the source, with everything the mapper and the analyzer need.
/// The buffer is only valid for the duration of delivery — never retain it.
public struct Frame {
    public let buffer: CVPixelBuffer
    public let timestamp: TimeInterval
    public let size: CGSize
    public let sensorRotation: SensorRotation
    public let mirrored: Bool

    public init(buffer: CVPixelBuffer,
                timestamp: TimeInterval,
                size: CGSize,
                sensorRotation: SensorRotation,
                mirrored: Bool) {
        self.buffer = buffer
        self.timestamp = timestamp
        self.size = size
        self.sensorRotation = sensorRotation
        self.mirrored = mirrored
    }
}
