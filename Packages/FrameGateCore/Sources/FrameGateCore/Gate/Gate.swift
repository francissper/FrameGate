//
//  Gate.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 13/09/26.
//

import Foundation

/// The gate decides when the shutter is enabled. A pure function from state and
/// measurements to a new state: no camera, no Combine, and no clock read inside
/// — the tick is passed in so a test can drive it frame by frame.
public enum Gate {

    public static func advance(_ state: GateState,
                               metrics: FrameMetrics,
                               thresholds: Thresholds,
                               holdFrames: Int,
                               stepCount: Int,
                               tick: Int) -> GateState {
        state
    }

    /// Called when the user presses the shutter. Only meaningful while `armed`.
    public static func fire(_ state: GateState, tick: Int) -> GateState {
        state
    }
}
