//
//  Inspector.swift
//  Fluid Simulation
//
//  Created by Max Van den Eynde on 06/04/2026.
//

import SwiftUI

private struct InspectorFocusKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

struct BoolInput: View {
    @Binding var value: Bool
    var title: String
    var body: some View {
        HStack {
            Text(title)

            Toggle(isOn: $value) {}
                .toggleStyle(.checkbox)
        }
    }
}

struct FloatInput: View {
    @Binding var value: Float
    var title: String

    var step: Float = 0.01
    var range: ClosedRange<Float> = -10_000 ... 10_000
    var decimals: Int = 2

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    @State private var dragStartValue: Float? = nil

    var body: some View {
        HStack {
            Text(title)

            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onAppear { syncTextFromValue() }
                .onChange(of: value) { _, _ in
                    if !isFocused { syncTextFromValue() }
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused { commitText() }
                }
                .onSubmit { commitText() }
                .overlay {
                    if !isFocused {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isFocused = true
                            }
                            .gesture(
                                DragGesture(minimumDistance: 2)
                                    .onChanged { gesture in
                                        if dragStartValue == nil {
                                            dragStartValue = value
                                        }
                                        let delta = Float(gesture.translation.width / 12) * step
                                        value = clamp(dragStartValue! + delta)
                                        syncTextFromValue()
                                    }
                                    .onEnded { _ in
                                        dragStartValue = nil
                                    }
                            )
                    }
                }
        }
    }

    private func commitText() {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        if let number = Float(normalized) {
            value = clamp(number)
        }
        syncTextFromValue()
    }

    private func syncTextFromValue() {
        text = String(format: "%.\(decimals)f", value)
    }

    private func clamp(_ v: Float) -> Float {
        min(max(v, range.lowerBound), range.upperBound)
    }
}

struct ColorInput: View {
    @Binding var value: NSColor
    var title: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            ColorPicker("", selection: Binding(
                get: { Color(value) },
                set: { value = NSColor($0) }
            ), supportsOpacity: true)
                .labelsHidden()
        }
    }
}

struct IntInput: View {
    @Binding var value: Int
    var title: String

    var step: Int = 1
    var range: ClosedRange<Int> = -10_000 ... 10_000

    @State private var text: String = ""
    @FocusState private var isFocused: Bool
    @State private var dragStartValue: Int? = nil

    var body: some View {
        HStack {
            Text(title)

            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onAppear { syncTextFromValue() }
                .onChange(of: value) { _, _ in
                    if !isFocused { syncTextFromValue() }
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused { commitText() }
                }
                .onSubmit { commitText() }
                .overlay {
                    if !isFocused {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isFocused = true
                            }
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 2)
                                    .onChanged { gesture in
                                        if dragStartValue == nil {
                                            dragStartValue = value
                                        }
                                        let delta = Int(gesture.translation.width / 12) * step
                                        value = clamp(dragStartValue! + delta)
                                        syncTextFromValue()
                                    }
                                    .onEnded { _ in
                                        dragStartValue = nil
                                    }
                            )
                    }
                }
        }
    }

    private func commitText() {
        if let number = Int(text) {
            value = clamp(number)
        }
        syncTextFromValue()
    }

    private func syncTextFromValue() {
        text = "\(value)"
    }

    private func clamp(_ v: Int) -> Int {
        min(max(v, range.lowerBound), range.upperBound)
    }
}

struct Vec2Input: View {
    @Binding var x: Float
    @Binding var y: Float
    var title: String
    var step: Float = 0.01
    var range: ClosedRange<Float> = -10_000 ... 10_000
    var decimals: Int = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                componentField(label: "X", value: $x)
                componentField(label: "Y", value: $y)
            }
        }
    }

    @ViewBuilder
    private func componentField(label: String, value: Binding<Float>) -> some View {
        HStack(spacing: 3) {
            FloatInput(
                value: value,
                title: label,
                step: step,
                range: range,
                decimals: decimals
            )
        }
    }
}

struct Vec3Input: View {
    @Binding var x: Float
    @Binding var y: Float
    @Binding var z: Float
    var title: String
    var step: Float = 0.01
    var range: ClosedRange<Float> = -10_000 ... 10_000
    var decimals: Int = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                componentField(label: "X", value: $x)
                componentField(label: "Y", value: $y)
                componentField(label: "Z", value: $z)
            }
        }
    }

    @ViewBuilder
    private func componentField(label: String, value: Binding<Float>) -> some View {
        HStack(spacing: 3) {
            FloatInput(
                value: value,
                title: label,
                step: step,
                range: range,
                decimals: decimals
            )
        }
    }
}

struct ControlsView: View {
    @Environment(Properties.self) var properties
    let renderer: Renderer

    @FocusState private var inspectorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Simulation Parameters")
                .bold()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 4)

            Text("Controls")
                .bold()
                .foregroundStyle(.gray)

            HStack {
                Spacer()
                Button {
                    properties.started = true
                    properties.isPaused.toggle()
                } label: {
                    Image(systemName: (properties.isPaused) ? "play.fill" : "pause.fill")
                }
                .keyboardShortcut(.space)
                Spacer()
            }

            Button("Log Particle Positions") {
                renderer.logParticlePositions()
            }

            Text("Particles")
                .bold()
                .foregroundStyle(.gray)

            FloatInput(
                value: Binding(
                    get: { properties.particleSize },
                    set: { properties.particleSize = $0 }
                ),
                title: "Size",
                step: 0.1
            )

            ColorInput(value: Binding(
                get: { properties.particleColor },
                set: { properties.particleColor = $0 }
            ), title: "Color")

            FloatInput(
                value: Binding(
                    get: { properties.spacing },
                    set: { properties.spacing = $0 }
                ),
                title: "Spacing",
                step: 0.1
            )
            
            FloatInput(
                value: Binding(
                    get: { properties.collisionDamping },
                    set: { properties.collisionDamping = $0 }
                ),
                title: "Collision Damping",
                step: 0.01
            )
            
            FloatInput(
                value: Binding(
                    get: { properties.gravity },
                    set: { properties.gravity = $0 }
                ),
                title: "Gravity",
                step: 0.1
            )
            
            FloatInput(
                value: Binding(
                    get: { properties.smoothingRadius },
                    set: { properties.smoothingRadius = $0 }
                ),
                title: "Smoothing Radius",
                step: 2
            )
            
            FloatInput(
                value: Binding(
                    get: { properties.pressureMultiplier},
                    set: { properties.pressureMultiplier = $0 }
                ),
                title: "Pressure Multiplier",
                step: 1,
                decimals: 2
            )

            
            FloatInput(
                value: Binding(
                    get: { properties.targetDensity },
                    set: { properties.targetDensity = $0 }
                ),
                title: "Target Density",
                step: 0.001,
                decimals: 4
            )
            
            FloatInput(
                value: Binding(
                    get: { properties.densityMultiplier },
                    set: { properties.densityMultiplier = $0 }
                ),
                title: "Density Multiplier",
                step: 2,
                decimals: 4
            )


            Vec2Input(
                x: Binding(
                    get: { properties.spawnArea.x },
                    set: { properties.spawnArea.x = $0 }
                ),
                y: Binding(
                    get: { properties.spawnArea.y },
                    set: { properties.spawnArea.y = $0 }
                ),
                title: "Spawn Area",
                step: 10.0
            )
            
            Vec2Input(
                x: Binding(
                    get: { properties.boundingBox.x },
                    set: { properties.boundingBox.x = $0 }
                ),
                y: Binding(
                    get: { properties.boundingBox.y },
                    set: { properties.boundingBox.y = $0 }
                ),
                title: "Bounds",
                step: 10.0
            )
            
            BoolInput(
                value: Binding(
                    get: { properties.generateRandomly },
                    set: { properties.generateRandomly = $0 }
                ),
                title: "Generate Randomly"
            )
            
            BoolInput(
                value: Binding(
                    get: { properties.enableCollisions },
                    set: { properties.enableCollisions = $0 }
                ),
                title: "Enable Collisions"
            )
            
            IntInput(
                value: Binding(
                    get: { properties.particleCount },
                    set: { properties.particleCount = $0 }
                ),
                title: "Particle Count",
                step: 1
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal)
        .contentShape(Rectangle())
        .onTapGesture {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }
}
