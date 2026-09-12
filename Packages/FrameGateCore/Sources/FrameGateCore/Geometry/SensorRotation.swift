//
//  SensorRotation.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 12/09/26.
//

/// How the sensor buffer is rotated relative to the device's natural orientation.
public enum SensorRotation: Int, Sendable, CaseIterable {
    case deg0 = 0
    case deg90 = 90
    case deg180 = 180
    case deg270 = 270
}
