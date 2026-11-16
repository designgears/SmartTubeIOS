import SwiftUI

// MARK: - TVPickerRow

/// One option in a tvOS Settings choice list.
struct TVChoice: Identifiable {
    let id = UUID()
    let label: String
    let isSelected: Bool
    let select: () -> Void
}

/// tvOS: a Settings row that looks like the system Settings app — a regular full-width row
/// (native focus highlight), title on the left, current value on the right. Selecting it
/// opens the `choices` as a list of buttons in a sheet (checkmark on the current one);
/// choosing one applies it and closes the sheet.
///
/// SwiftUI `Picker` can't be used for this on tvOS here: navigation-link pickers push a
/// blank page inside the sidebar TabView (and Menu then exits the app), inline/menu pickers
/// render no options or an inset pill. On other platforms this is the picker unchanged.
struct TVPickerRow<P: View>: View {
    private let title: Text
    private let value: String?
    private let dot: Color?
    private let choices: [TVChoice]
    private let picker: () -> P
    @State private var showOptions = false

    init(
        _ title: LocalizedStringKey, value: String? = nil, dot: Color? = nil, choices: [TVChoice] = [],
        @ViewBuilder picker: @escaping () -> P
    ) {
        self.title = Text(title)
        self.value = value
        self.dot = dot
        self.choices = choices
        self.picker = picker
    }

    @_disfavoredOverload
    init<S: StringProtocol>(
        _ title: S, value: String? = nil, dot: Color? = nil, choices: [TVChoice] = [],
        @ViewBuilder picker: @escaping () -> P
    ) {
        self.title = Text(title)
        self.value = value
        self.dot = dot
        self.choices = choices
        self.picker = picker
    }

    var body: some View {
        #if os(tvOS)
        Button {
            showOptions = true
        } label: {
            HStack(spacing: 18) {
                if let dot {
                    Circle().fill(dot).frame(width: 14, height: 14)
                }
                title
                Spacer(minLength: 24)
                if let value {
                    Text(value).foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $showOptions) {
            VStack(alignment: .leading, spacing: 28) {
                title.font(.title2.weight(.bold))
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(choices) { choice in
                            Button {
                                choice.select()
                                showOptions = false
                            } label: {
                                HStack {
                                    Text(choice.label)
                                    Spacer()
                                    if choice.isSelected {
                                        Image(systemName: "checkmark")
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                }
                .scrollClipDisabled()
            }
            .padding(60)
            .frame(width: 900)
            .frame(maxHeight: 820)
        }
        #else
        picker()
        #endif
    }
}

/// Builds the tvOS option list for a `TVPickerRow` from a binding and its values.
func tvChoices<V: Equatable>(_ binding: Binding<V>, _ values: [V], label: (V) -> String) -> [TVChoice] {
    values.map { value in
        TVChoice(label: label(value), isSelected: binding.wrappedValue == value) {
            binding.wrappedValue = value
        }
    }
}
