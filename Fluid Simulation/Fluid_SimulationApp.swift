//
//  Fluid_SimulationApp.swift
//  Fluid Simulation
//
//  Created by Max Van den Eynde on 06/04/2026.
//

import SwiftUI

@main
struct Fluid_SimulationApp: App {
    @State var properties: Properties = .init()
    @Environment(\.openWindow) var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(properties)
        }
    }
}
