//
//  ContentView.swift
//  Fluid Simulation
//
//  Created by Max Van den Eynde on 06/04/2026.
//

import SwiftUI

struct ContentView: View {
    @Environment(Properties.self) var properties
    @State private var showInpsector = true
    @State private var renderer = Renderer()

    var body: some View {
        VStack {
            Viewport(renderer: renderer)
                .environment(properties)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(properties)
        .inspector(isPresented: $showInpsector) {
            ControlsView(renderer: renderer)
                .environment(properties)
                .inspectorColumnWidth(min: 220, ideal: 280, max: 360)
                .padding()
        }
        .toolbar {
            Button("Toggle Sidebar") {
                showInpsector.toggle()
            }
        }
    }
}
