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

struct FloatInput: View {
    @Binding var value: Float
    var title: String

    var step: Float = 0.01
    var range: ClosedRange<Float> = -10_000 ... 10_000
    var decimals: Int = 3

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
    var decimals: Int = 3

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
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .frame(width: 10)
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
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .frame(width: 10)
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
                    Image(systemName: properties.isPaused ? "play.fill" : "pause.fill")
                }
                .keyboardShortcut(.space)
                Spacer()
            }

            Text("Particles")
                .bold()
                .foregroundStyle(.gray)

            FloatInput(
                value: Binding(
                    get: { properties.particleSize },
                    set: { properties.particleSize = $0 }
                ),
                title: "Size"
            )

            ColorInput(value: Binding(
                get: { properties.particleColor },
                set: { properties.particleColor = $0 }
            ), title: "Color")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal)
        .contentShape(Rectangle())
        .onTapGesture {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }
}
