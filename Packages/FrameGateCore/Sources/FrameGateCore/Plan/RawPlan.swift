//
//  RawPlan.swift
//  FrameGateCore
//
//  Created by Franciss Peralta on 12/09/26.
//

import Foundation

/// A permissive mirror of the payload: everything optional, nothing validated.
struct RawPlan: Decodable {
    let planId: String?
    let createdAt: String?
    let steps: [RawStep]?

    init(from decoder: Decoder) throws {
        var container = LenientContainer(
            try decoder.container(keyedBy: AnyCodingKey.self)
        )
        self.planId = container.decodeIfPresent(String.self, "planId")
        self.createdAt = container.decodeIfPresent(String.self, "createdAt")
        self.steps = container.decodeIfPresent([RawStep].self, "steps")
    }
}

/// Captures a step's container without reading it, so validation owns every rule.
struct RawStep: Decodable {
    let container: LenientContainer

    init(from decoder: Decoder) throws {
        self.container = LenientContainer(
            try decoder.container(keyedBy: AnyCodingKey.self)
        )
    }
}
