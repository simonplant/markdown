import SwiftUI
import EMSettings

/// Settings screen presented as a sheet per [A-058].
struct SettingsView: View {
    @Environment(SettingsManager.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            settingsForm
                .navigationTitle("Settings")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }

    private var settingsForm: some View {
        @Bindable var settings = settings
        return Form {
            Section("Appearance") {
                Picker("Color Scheme", selection: $settings.preferredColorScheme) {
                    Text("System").tag(ColorSchemePreference.system)
                    Text("Light").tag(ColorSchemePreference.light)
                    Text("Dark").tag(ColorSchemePreference.dark)
                }
                .accessibilityHint("Choose light, dark, or system color scheme")
            }

            Section("Editor") {
                Toggle("Spell Check", isOn: $settings.isSpellCheckEnabled)
                    .accessibilityHint("Enable or disable spell checking in the editor")

                Toggle("Auto-Format", isOn: $settings.isAutoFormatEnabled)
                    .accessibilityHint("Enable or disable automatic list and table formatting")
            }

            Section {
                Text("easy-markdown")
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Version 1.0")
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
