import SwiftUI
import TortoiseBlocksKit
import TortoiseUI

/// Preset emoji offered as instant variable names — deliberately from the
/// SMP plane so (like 🐢) they are valid Swift identifiers in the generated
/// code; BMP lookalikes such as ⭐ (U+2B50) or ❤️ (U+2764) are not.
let variableNamePresets = ["🌟", "💖", "🍀"]

/// Display-length cap for typed variable names.
let variableNameMaxLength = 10

/// A slot's "chip" look on the workspace's dark, category-colored block rows
/// (§21): a white capsule with dark text, so it stays readable regardless of
/// which category color it's sitting on — the same kind of fixed-color
/// choice already made for `BlockCategory.color` itself, not a semantic one.
///
/// Applied ambiently to the whole block list (`WorkspaceView`), not to
/// individual buttons here — these same slot views (`NumberValueButton`,
/// `ComparisonButton`, `VariableNameButton`, `ConditionButton`) are also
/// reused inside `ConditionEditor`'s popover, which sits on the system's
/// light popover background rather than a block, and resets back to
/// `.bordered` for that subtree.
struct WorkspaceChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.black)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                Color.white.opacity(configuration.isPressed ? 0.75 : 0.92),
                in: .capsule
            )
    }
}

extension View {
    /// Standard chrome for a slot editor's popover. Resets the foreground to
    /// the adaptive label color (#24): the block row sets `.foregroundStyle
    /// (.white)`, which otherwise leaks into the popover and leaves the label,
    /// text field, and stepper invisible on the system background.
    ///
    /// `Color.primary` (the absolute label color), *not* the hierarchical
    /// `.primary` — the latter is the primary *level* of the inherited base
    /// style, so against a white base it resolves to white and doesn't fix
    /// anything. `.tint` likewise restores control coloring for the stepper.
    func slotPopoverContent() -> some View {
        foregroundStyle(Color.primary)
            .tint(Color.accentColor)
            .padding()
            .presentationCompactAdaptation(.popover)
    }
}

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
            HStack(spacing: 4) {
                // A box glyph marks a *value read from* a box (#24), so it
                // isn't mistaken for the bare-name box target it sits next
                // to in "Add to Box [🌟] [💖]".
                if case .variable = value {
                    Image(systemName: "shippingbox")
                        .imageScale(.small)
                }
                Text(displayText)
                    .font(.body.monospacedDigit())
            }
        }
        .pointerHover()
        .popover(isPresented: $showsEditor) {
            NumberValueEditor(value: value, usedNames: usedNames, onChange: onChange)
                .buttonStyle(.bordered)
                .slotPopoverContent()
        }
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityHint("Tap to change the number")
    }

    private var displayText: String { numberValueDisplayText(value) }

    private var accessibilityLabel: String {
        if case .variable(let name) = value {
            return String(localized: "Value of box \(name)")
        }
        return String(localized: "Number \(displayText)")
    }
}

/// Display text for a `NumberValue` — shared by `NumberValueButton`'s own
/// chip and `ConditionButton`'s summary chip, so the two read consistently.
func numberValueDisplayText(_ value: NumberValue) -> String {
    switch value {
    case .literal(let value):
        format(value)
    case .random(let min, let max):
        "🎲 \(format(min))–\(format(max))"
    case .variable(let name):
        name
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
                    // ±1 for fine nudges; the keyboard handles big jumps.
                    NumberField(value: number, step: 1) { onChange(.literal($0)) }
                }
            case .random(let min, let max):
                LabeledContent("Minimum") {
                    NumberField(value: min) { onChange(.random(min: $0, max: max)) }
                }
                LabeledContent("Maximum") {
                    NumberField(value: max) { onChange(.random(min: min, max: $0)) }
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

}

/// A numeric text field, optionally with a ± stepper, that commits when
/// editing ends — on Return and on losing focus, which is what fires when
/// the enclosing popover is dismissed (#24). Committing on focus loss (not
/// only on Return) means a typed number is never silently dropped by closing
/// the popover. The stepper shares the field's own text, so ± updates the
/// visible value immediately rather than round-tripping through the document.
/// Shows the number pad on iOS; invalid text reverts to the last good value.
struct NumberField: View {
    let value: Double
    var step: Double? = nil
    let onCommit: (Double) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool
    @ScaledMetric private var fieldWidth: CGFloat = 80

    var body: some View {
        HStack(spacing: 8) {
            TextField("Number", text: $text)
                .textFieldStyle(.roundedBorder)
                .numericKeyboard()
                .frame(width: fieldWidth)
                .focused($focused)
                .onAppear { text = format(value) }
                // value only changes from a committed edit (this field, the
                // stepper, or undo) — never mid-typing, since typing doesn't
                // commit — so mirroring it here can't clobber in-progress
                // input.
                .onChange(of: value) { _, new in text = format(new) }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commit() }
                }
                .onSubmit { commit() }
            if let step {
                Stepper("Number", value: stepperBinding, step: step)
                    .labelsHidden()
            }
        }
    }

    /// Drives the stepper off the committed `value`, but writes both the
    /// visible text and the commit so ± reflects instantly.
    private var stepperBinding: Binding<Double> {
        Binding(
            get: { value },
            set: { new in
                text = format(new)
                onCommit(new)
            }
        )
    }

    private func commit() {
        guard let parsed = Double(text.trimmingCharacters(in: .whitespaces)) else {
            text = format(value)
            return
        }
        if parsed != value { onCommit(parsed) }
    }
}

/// The if header's argument slot: a single summary chip (e.g. "🎲1–6 ≥ 4"),
/// following the same "chip → popover" language as `NumberValueButton` and
/// `ColorValueButton`. The popover hosts the existing three-slot
/// `ConditionEditor` unchanged.
struct ConditionButton: View {
    let condition: Condition
    let usedNames: [String]
    let onChange: (Condition) -> Void

    @State private var showsEditor = false

    var body: some View {
        Button {
            showsEditor = true
        } label: {
            Text(displayText)
                .font(.body.monospacedDigit())
        }
        .pointerHover()
        .popover(isPresented: $showsEditor) {
            HStack(spacing: 8) {
                ConditionEditor(condition: condition, usedNames: usedNames, onChange: onChange)
            }
            // ConditionEditor's own NumberValueButton/ComparisonButton
            // default to the dark-row chip look; reset to `.bordered` here
            // since this popover sits on the system's background, not a
            // category-colored block.
            .buttonStyle(.bordered)
            .slotPopoverContent()
        }
        .accessibilityLabel(Text("Condition \(displayText)"))
        .accessibilityHint("Tap to change the condition")
    }

    private var displayText: String {
        "\(numberValueDisplayText(condition.lhs)) \(comparisonSymbol(condition.comparison)) \(numberValueDisplayText(condition.rhs))"
    }
}

/// The if header's argument cells: lhs, comparison, rhs — three siblings
/// laid out by the surrounding header HStack.
struct ConditionEditor: View {
    let condition: Condition
    let usedNames: [String]
    let onChange: (Condition) -> Void

    var body: some View {
        NumberValueButton(value: condition.lhs, usedNames: usedNames) { new in
            var condition = condition
            condition.lhs = new
            onChange(condition)
        }
        ComparisonButton(comparison: condition.comparison) { new in
            var condition = condition
            condition.comparison = new
            onChange(condition)
        }
        NumberValueButton(value: condition.rhs, usedNames: usedNames) { new in
            var condition = condition
            condition.rhs = new
            onChange(condition)
        }
    }
}

/// Argument slot for a comparison: shows the language-neutral symbol, picks
/// from a menu of spelled-out choices.
struct ComparisonButton: View {
    let comparison: Comparison
    let onChange: (Comparison) -> Void

    var body: some View {
        Menu {
            Picker(
                "Comparison",
                selection: Binding(get: { comparison }, set: { onChange($0) })
            ) {
                ForEach(Comparison.allCases, id: \.self) { comparison in
                    Text(comparisonName(comparison)).tag(comparison)
                }
            }
        } label: {
            Text(comparisonSymbol(comparison))
        }
        .menuStyle(.button)
        .fixedSize()
        .pointerHover()
        .accessibilityLabel(Text(comparisonName(comparison)))
        .accessibilityHint("Tap to choose a comparison")
    }
}

/// Display symbol for a comparison — language-neutral, so the block row
/// reads naturally in both English and Japanese word order.
func comparisonSymbol(_ comparison: Comparison) -> String {
    switch comparison {
    case .less: "<"
    case .lessOrEqual: "≤"
    case .equal: "="
    case .greaterOrEqual: "≥"
    case .greater: ">"
    }
}

/// Localized spelled-out name for a comparison (menu / accessibility).
func comparisonName(_ comparison: Comparison) -> String {
    switch comparison {
    case .less: String(localized: "less than")
    case .lessOrEqual: String(localized: "or less")
    case .equal: String(localized: "equal to")
    case .greaterOrEqual: String(localized: "or more")
    case .greater: String(localized: "greater than")
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
        .pointerHover()
        .popover(isPresented: $showsEditor) {
            VariableNamePicker(selected: name, usedNames: usedNames) { new in
                onChange(new)
                showsEditor = false
            }
            .buttonStyle(.bordered)
            .slotPopoverContent()
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
    @ScaledMetric private var swatch: CGFloat = 20

    var body: some View {
        Button {
            showsEditor = true
        } label: {
            switch value {
            case .literal(let color):
                // A white ring keeps the swatch legible against the row's
                // own (now solid, saturated) category color.
                Circle()
                    .fill(Color(color.tortoiseColor))
                    .stroke(.white, lineWidth: 1.5)
                    .frame(width: swatch, height: swatch)
            case .random:
                Circle()
                    .fill(.white.opacity(0.92))
                    .frame(width: swatch, height: swatch)
                    .overlay { Text("🎲").font(.caption) }
            }
        }
        .buttonStyle(.plain)
        .pointerHover()
        .popover(isPresented: $showsEditor) {
            ColorSwatchGrid(selected: value) { new in
                onChange(new)
                showsEditor = false
            }
            .slotPopoverContent()
        }
        .accessibilityLabel(Text("Color \(colorValueName(value))"))
        .accessibilityHint("Tap to choose a color")
    }
}

struct ColorSwatchGrid: View {
    let selected: ColorValue
    let onSelect: (ColorValue) -> Void

    @ScaledMetric private var swatch: CGFloat = 28

    // Computed (not stored) so the columns track `swatch` as Dynamic Type
    // scales it; the +8 keeps the cell gutter proportional.
    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(swatch + 8)), count: 5)
    }

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
                        .frame(width: swatch, height: swatch)
                }
                .buttonStyle(.plain)
                .pointerHover()
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
                    .frame(width: swatch, height: swatch)
                    .overlay { Text("🎲") }
            }
            .buttonStyle(.plain)
            .pointerHover()
            .accessibilityLabel(Text("Dice"))
        }
    }
}

/// Localized display name for a palette color.
///
/// A `switch` over static literals, not `String(localized:
/// String.LocalizationValue(color.rawValue))` — Xcode's string extraction
/// can't see through a dynamically-built key, so it judged those entries
/// unused and pruned their Japanese translations the next time the catalog
/// was resynced. Static literals per case (matching `comparisonName`
/// below) keep the keys visible to that extraction.
func colorName(_ color: BlockColor) -> String {
    switch color {
    case .black: String(localized: "black")
    case .white: String(localized: "white")
    case .red: String(localized: "red")
    case .green: String(localized: "green")
    case .blue: String(localized: "blue")
    case .yellow: String(localized: "yellow")
    case .orange: String(localized: "orange")
    case .purple: String(localized: "purple")
    case .cyan: String(localized: "cyan")
    case .magenta: String(localized: "magenta")
    }
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
