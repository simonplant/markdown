import SwiftUI

/// User appearance/font preferences (FEAT-044 custom themes & fonts), persisted
/// in UserDefaults. Read by the editor views and the app's color scheme.
enum AppSettings {
  static let appearanceKey = "appearance"      // "system" | "light" | "dark"
  static let fontSizeKey = "editorFontSize"    // CGFloat, default 16

  static var fontSize: CGFloat {
    let v = UserDefaults.standard.double(forKey: fontSizeKey)
    return v == 0 ? 16 : CGFloat(v)
  }

  static func colorScheme(_ raw: String) -> ColorScheme? {
    switch raw {
    case "light": return .light
    case "dark": return .dark
    default: return nil // system
    }
  }
}

/// Settings sheet: appearance (system/light/dark) + editor font size.
struct SettingsView: View {
  @AppStorage(AppSettings.appearanceKey) private var appearance = "system"
  @AppStorage(AppSettings.fontSizeKey) private var fontSize = 16.0
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section("Appearance") {
          Picker("Theme", selection: $appearance) {
            Text("System").tag("system")
            Text("Light").tag("light")
            Text("Dark").tag("dark")
          }
          .pickerStyle(.segmented)
        }
        Section("Editor") {
          Stepper("Font size: \(Int(fontSize)) pt", value: $fontSize, in: 10...28, step: 1)
        }
      }
      .navigationTitle("Settings")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    .presentationDetents([.medium])
  }
}
