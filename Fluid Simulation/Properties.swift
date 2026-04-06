//
//  Properties.swift
//  Fluid Simulation
//
//  Created by Max Van den Eynde on 06/04/2026.
//

import Observation
import SwiftUI

@Observable
final class Properties {
    var isPaused: Bool = true
    var started: Bool = false

    var particleSize: Float = 30.0
    var spacing: Float = 6.0
    var spawnArea: simd_float2 = .init(repeating: 500.0)
    var boundingBox: simd_float2 = .init(2200.0, 1300.0)
    var particleColor: NSColor = .cyan
}
