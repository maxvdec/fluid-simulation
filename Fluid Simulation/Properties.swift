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
    var particleCount: Int = 1
    var particleColor: NSColor = .cyan
}
