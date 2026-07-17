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
        .accessibilityLabel("すうじ \(displayText)")
        .accessibilityHint("タップしてすうじをかえます")
    }

    private var displayText: String {
        switch value {
        case .literal(let value):
            format(value)
        case .random(let min, let max):
            "🎲 \(format(min))〜\(format(max))"
        }
    }
}

struct NumberValueEditor: View {
    let value: NumberValue
    let onChange: (NumberValue) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("しゅるい", selection: isRandom) {
                Text("すうじ").tag(false)
                Text("サイコロ").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch value {
            case .literal(let number):
                LabeledContent("すうじ") {
                    HStack {
                        TextField("すうじ", value: literalBinding(number), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Stepper("すうじ", value: literalBinding(number), step: 10)
                            .labelsHidden()
                    }
                }
            case .random(let min, let max):
                LabeledContent("さいしょう") {
                    TextField(
                        "さいしょう", value: randomBinding(min: min, max: max, edits: .min),
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                }
                LabeledContent("さいだい") {
                    TextField(
                        "さいだい", value: randomBinding(min: min, max: max, edits: .max),
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
struct ColorValueButton: View {
    let color: BlockColor
    let onChange: (BlockColor) -> Void

    @State private var showsEditor = false

    var body: some View {
        Button {
            showsEditor = true
        } label: {
            Circle()
                .fill(Color(color.tortoiseColor))
                .stroke(.secondary, lineWidth: 1)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsEditor) {
            ColorSwatchGrid(selected: color) { new in
                onChange(new)
                showsEditor = false
            }
            .padding()
            .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel("いろ \(color.rawValue)")
        .accessibilityHint("タップしていろをえらびます")
    }
}

struct ColorSwatchGrid: View {
    let selected: BlockColor
    let onSelect: (BlockColor) -> Void

    private let columns = Array(repeating: GridItem(.fixed(36)), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(BlockColor.allCases, id: \.self) { color in
                Button {
                    onSelect(color)
                } label: {
                    Circle()
                        .fill(Color(color.tortoiseColor))
                        .stroke(
                            color == selected ? Color.accentColor : .secondary,
                            lineWidth: color == selected ? 3 : 1
                        )
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.rawValue)
            }
        }
    }
}

/// Formats a number for display: integral values without the trailing `.0`.
func format(_ value: Double) -> String {
    if value == value.rounded(), abs(value) < 1e15 {
        return String(Int(value))
    }
    return String(value)
}
