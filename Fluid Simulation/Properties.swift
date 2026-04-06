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

    var particleSize: Float = 1.0
    var gravity: Float = 0
    var spacing: Float = 0.3
    var spawnArea: simd_float2 = .init(repeating: 20.0)
    var boundingBox: simd_float2 = .init(90.0, 60.0)
    var particleColor: NSColor = .darkGray
    var collisionDamping: Float = 0.0
    var generateRandomly: Bool = true
    var particleCount: Int = 400
    var enableCollisions = true
    var smoothingRadius: Float = 5.0
    var targetDensity: Float = 2.5
    var pressureMultiplier: Float = 50
    var densityMultiplier: Float = 1
}
