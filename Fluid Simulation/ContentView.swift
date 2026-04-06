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

    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
        }
        .padding()
        .environment(properties)
        .inspector(isPresented: $showInpsector) {
            ControlsView()
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
