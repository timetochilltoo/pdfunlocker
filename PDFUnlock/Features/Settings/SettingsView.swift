import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var bindable = settings

        Form {
            Section("Output") {
                Picker("Location", selection: $bindable.outputLocation) {
                    ForEach(AppSettings.OutputLocation.allCases) { loc in
                        Text(loc.displayName).tag(loc)
                    }
                }

                if settings.outputLocation == .customFolder {
                    HStack {
                        Text(settings.customOutputFolder?.path ?? "Not set")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Choose…") {
                            pickCustomFolder()
                        }
                    }
                }

                TextField("Unlock suffix", text: $bindable.unlockSuffix)
                TextField("Convert suffix", text: $bindable.convertSuffix)

                Picker("Existing files", selection: $bindable.collisionBehavior) {
                    ForEach(AppSettings.CollisionBehavior.allCases) { b in
                        Text(b.displayName).tag(b)
                    }
                }
            }

            Section("Convert") {
                Picker("Default PNG DPI", selection: $bindable.defaultPNGDPI) {
                    Text("72").tag(72)
                    Text("150").tag(150)
                    Text("300").tag(300)
                }
                Toggle("Default enable Markdown (experimental)", isOn: $bindable.defaultMarkdown)
            }

            Section("Recovery") {
                Stepper(
                    "Max attempts: \(settings.recoveryMaxAttempts)",
                    value: $bindable.recoveryMaxAttempts,
                    in: 1...1_000_000,
                    step: 1_000
                )
                Stepper(
                    "Max seconds: \(settings.recoveryMaxSeconds)",
                    value: $bindable.recoveryMaxSeconds,
                    in: 1...600
                )
                Toggle("Enable pattern mutations", isOn: $bindable.recoveryMutations)
            }

            Section("Batch") {
                Stepper(
                    "Concurrency: \(settings.concurrency)",
                    value: $bindable.concurrency,
                    in: 1...4
                )
            }
        }
        .formStyle(.grouped)
    }

    private func pickCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Output Folder"
        if panel.runModal() == .OK, let url = panel.url {
            settings.customOutputFolder = url
        }
    }
}