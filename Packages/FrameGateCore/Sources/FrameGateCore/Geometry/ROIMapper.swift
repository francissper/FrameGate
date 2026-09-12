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
        MappedRegion(buffer: .zero, view: .zero)
    }
}
