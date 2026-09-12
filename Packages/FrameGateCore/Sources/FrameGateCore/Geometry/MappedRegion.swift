//
//  MappedRegion.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 12/09/26.
//

import CoreGraphics

public struct MappedRegion: Equatable, Sendable {
    /// Where to measure, in pixel coordinates of the buffer.
    public let buffer: CGRect
    /// Where to draw, in points of the view.
    public let view: CGRect
}
