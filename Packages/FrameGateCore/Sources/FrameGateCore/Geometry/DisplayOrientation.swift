//
//  DisplayOrientation.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 12/09/26.
//

/// Defined here rather than reusing UIInterfaceOrientation so Core stays free of UIKit.
public enum DisplayOrientation: Sendable, CaseIterable {
    case portrait
    case portraitUpsideDown
    case landscapeLeft
    case landscapeRight
}
