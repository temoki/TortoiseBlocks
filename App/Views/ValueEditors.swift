import SwiftUI
import TortoiseBlocksKit
import TortoiseUI

/// Argument slot for a `NumberValue`: shows the current value, edits in a
/// popover, and can flip between a literal and the dice (random) form.
struct NumberValueButton: View {
    let value: NumberValue
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
            NumberValueEditor(value: value, onChange: onChange)
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
        }
    }
}

struct NumberValueEditor: View {
    let value: NumberValue
    let onChange: (NumberValue) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Type", selection: isRandom) {
                Text("Number").tag(false)
                Text("Dice").tag(true)
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
            }
        }
        .frame(minWidth: 220)
    }

    private var isRandom: Binding<Bool> {
        Binding(
            get: {
                if case .random = value { return true }
                return false
            },
            set: { random in
                switch (random, value) {
                case (true, .literal(let number)):
                    // Seed a friendly range around the literal.
                    onChange(.random(min: max(0, number - 50), max: number + 50))
                case (false, .random(let min, let max)):
                    onChange(.literal(((min + max) / 2).rounded()))
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
