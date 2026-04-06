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
    var isPaused: Bool = false
    var started: Bool = false

    var particleSize: Float = 1.0
    var particleColor: NSColor = .blue
}
