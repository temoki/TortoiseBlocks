import SwiftUI
import TortoiseBlocksKit
import TortoiseUI

/// Preset emoji offered as instant variable names — deliberately from the
/// SMP plane so (like 🐢) they are valid Swift identifiers in the generated
/// code; BMP lookalikes such as ⭐ (U+2B50) or ❤️ (U+2764) are not.
let variableNamePresets = ["🌟", "💖", "🍀"]

/// Display-length cap for typed variable names.
let variableNameMaxLength = 10

/// Argument slot for a `NumberValue`: shows the current value, edits in a
/// popover, and can flip between a literal, the dice (random) form, and a
/// variable ("box") reference. `usedNames` are the variables already in the
/// program, offered as quick choices.
struct NumberValueButton: View {
    let value: NumberValue
    let usedNames: [String]
    let onChange: (NumberValue) -> Void

    @State private var showsEditor = false

    var body: some View {
        Button {
            showsEditor = true
        } label: {
            Text(displayText)
                .font(.body.monospacedDigit())
        }
        .buttonStyle(.bordered)
        .popover(isPresented: $showsEditor) {
            NumberValueEditor(value: value, usedNames: usedNames, onChange: onChange)
                .padding()
                .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel(Text("Number \(displayText)"))
        .accessibilityHint("Tap to change the number")
    }

    private var displayText: String {
        switch value {
        case .literal(let value):
            format(value)
        case .random(let min, let max):
            "🎲 \(format(min))–\(format(max))"
        case .variable(let name):
            name
        }
    }
}

struct NumberValueEditor: View {
    let value: NumberValue
    let usedNames: [String]
    let onChange: (NumberValue) -> Void

    private enum ValueForm: Hashable { case literal, random, variable }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Type", selection: form) {
                Text("Number").tag(ValueForm.literal)
                Text("Dice").tag(ValueForm.random)
                Text("Box").tag(ValueForm.variable)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch value {
            case .literal(let number):
                LabeledContent("Number") {
                    HStack {
                        TextField("Number", value: literalBinding(number), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Stepper("Number", value: literalBinding(number), step: 10)
                            .labelsHidden()
                    }
                }
            case .random(let min, let max):
                LabeledContent("Minimum") {
                    TextField(
                        "Minimum", value: randomBinding(min: min, max: max, edits: .min),
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                }
                LabeledContent("Maximum") {
                    TextField(
                        "Maximum", value: randomBinding(min: min, max: max, edits: .max),
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                }
            case .variable(let name):
                VariableNamePicker(selected: name, usedNames: usedNames) {
                    onChange(.variable($0))
                }
            }
        }
        .frame(minWidth: 220)
    }

    private var form: Binding<ValueForm> {
        Binding(
            get: {
                switch value {
                case .literal: .literal
                case .random: .random
                case .variable: .variable
                }
            },
            set: { newForm in
                switch (newForm, value) {
                case (.literal, .random(let min, let max)):
                    onChange(.literal(((min + max) / 2).rounded()))
                case (.literal, .variable):
                    // Boxes start at 0, so that's the natural way back.
                    onChange(.literal(0))
                case (.random, .literal(let number)):
                    // Seed a friendly range around the literal.
                    onChange(.random(min: max(0, number - 50), max: number + 50))
                case (.random, .variable):
                    onChange(.random(min: 0, max: 100))
                case (.variable, .literal), (.variable, .random):
                    onChange(.variable(usedNames.first ?? variableNamePresets[0]))
                default:
                    break
                }
            }
        )
    }

    private func literalBinding(_ number: Double) -> Binding<Double> {
        Binding(get: { number }, set: { onChange(.literal($0)) })
    }

    private enum RandomEdge { case min, max }

    private func randomBinding(min: Double, max: Double, edits edge: RandomEdge)
        -> Binding<Double>
    {
        Binding(
            get: { edge == .min ? min : max },
            set: { new in
                onChange(edge == .min ? .random(min: new, max: max) : .random(min: min, max: new))
            }
        )
    }
}

/// Argument slot for a variable name: shows the current name and edits in a
/// popover.
struct VariableNameButton: View {
    let name: String
    let usedNames: [String]
    let onChange: (String) -> Void

    @State private var showsEditor = false

    var body: some View {
        Button {
            showsEditor = true
        } label: {
            Text(name)
        }
        .buttonStyle(.bordered)
        .popover(isPresented: $showsEditor) {
            VariableNamePicker(selected: name, usedNames: usedNames) { new in
                onChange(new)
                showsEditor = false
            }
            .padding()
            .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel(Text("Box \(name)"))
        .accessibilityHint("Tap to choose a box")
    }
}

/// Name chooser shared by `VariableNameButton` and the number editor's box
/// form: preset emoji + every name the program already uses, plus a free
/// text field for a brand-new name.
struct VariableNamePicker: View {
    let selected: String
    let usedNames: [String]
    let onSelect: (String) -> Void

    @State private var customName = ""

    private let columns = [GridItem(.adaptive(minimum: 44), alignment: .leading)]

    private var choices: [String] {
        var choices = variableNamePresets
        for name in usedNames where !choices.contains(name) {
            choices.append(name)
        }
        return choices
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(choices, id: \.self) { name in
                    let isSelected = name == selected
                    Button {
                        onSelect(name)
                    } label: {
                        Text(name)
                            .lineLimit(1)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(
                                isSelected
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.secondary.opacity(0.1),
                                in: .rect(cornerRadius: 8)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        isSelected ? Color.accentColor : .secondary,
                                        lineWidth: isSelected ? 2 : 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Box \(name)"))
                }
            }
            HStack {
                TextField("New Name", text: $customName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .onSubmit(commitCustomName)
                Button("Use", systemImage: "checkmark") {
                    commitCustomName()
                }
                .disabled(trimmedCustomName.isEmpty)
            }
        }
        .frame(minWidth: 220)
    }

    private var trimmedCustomName: String {
        customName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commitCustomName() {
        let name = String(trimmedCustomName.prefix(variableNameMaxLength))
        guard !name.isEmpty else { return }
        onSelect(name)
    }
}

/// Argument slot for a `BlockColor`: a swatch that opens a palette popover.
/// Argument slot for a `ColorValue`: a swatch (or dice, for random) that
/// opens a palette popover.
struct ColorValueButton: View {
    let value: ColorValue
    let onChange: (ColorValue) -> Void

    @State private var showsEditor = false

    var body: some View {
        Button {
            showsEditor = true
        } label: {
            switch value {
            case .literal(let color):
                Circle()
                    .fill(Color(color.tortoiseColor))
                    .stroke(.secondary, lineWidth: 1)
                    .frame(width: 20, height: 20)
            case .random:
                Text("🎲")
                    .frame(width: 20, height: 20)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsEditor) {
            ColorSwatchGrid(selected: value) { new in
                onChange(new)
                showsEditor = false
            }
            .padding()
            .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel(Text("Color \(colorValueName(value))"))
        .accessibilityHint("Tap to choose a color")
    }
}

struct ColorSwatchGrid: View {
    let selected: ColorValue
    let onSelect: (ColorValue) -> Void

    private let columns = Array(repeating: GridItem(.fixed(36)), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(BlockColor.allCases, id: \.self) { color in
                let isSelected = selected == .literal(color)
                Button {
                    onSelect(.literal(color))
                } label: {
                    Circle()
                        .fill(Color(color.tortoiseColor))
                        .stroke(
                            isSelected ? Color.accentColor : .secondary,
                            lineWidth: isSelected ? 3 : 1
                        )
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(colorName(color)))
            }
            let isRandomSelected = selected == .random
            Button {
                onSelect(.random)
            } label: {
                Circle()
                    .fill(.secondary.opacity(0.15))
                    .stroke(
                        isRandomSelected ? Color.accentColor : .secondary,
                        lineWidth: isRandomSelected ? 3 : 1
                    )
                    .frame(width: 28, height: 28)
                    .overlay { Text("🎲") }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Dice"))
        }
    }
}

/// Localized display name for a palette color (keys are the raw values).
func colorName(_ color: BlockColor) -> String {
    String(localized: String.LocalizationValue(color.rawValue))
}

/// Localized display name for a `ColorValue` — a palette color, or "Dice"
/// for the random case.
func colorValueName(_ value: ColorValue) -> String {
    switch value {
    case .literal(let color):
        colorName(color)
    case .random:
        String(localized: "Dice")
    }
}

/// Formats a number for display: integral values without the trailing `.0`.
func format(_ value: Double) -> String {
    if value == value.rounded(), abs(value) < 1e15 {
        return String(Int(value))
    }
    return String(value)
}
