import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var lib: Library
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var key = ""
    @State private var confirmRemove = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Download all recordings automatically", isOn: $lib.autoDownload)
                } footer: {
                    Text(lib.autoDownload
                         ? "New recordings download by themselves when you open the app."
                         : "Pick recordings yourself with the arrow next to each one.")
                }

                Section("On this phone") {
                    LabeledContent("Recordings", value: "\(lib.downloadedCount) of \(lib.totalCount)")
                    LabeledContent("Space used", value: Fmt.bytes(lib.bytesOnPhone))
                    Button("Remove all downloads", role: .destructive) { confirmRemove = true }
                }

                Section {
                    TextField("Google Drive folder link", text: $link, axis: .vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("API key (optional)", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save and refresh") {
                        lib.folderID = DriveSource.folderID(fromLink: link)
                        lib.apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task { await lib.refresh() }
                    }
                } header: {
                    Text("Google Drive")
                } footer: {
                    Text("The folder that holds the usool, Tafsir and Hidayatn Nahv folders, shared as \"Anyone with the link\".")
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { link = lib.folderID; key = lib.apiKey }
            .confirmationDialog("Remove every recording from this phone?", isPresented: $confirmRemove,
                                titleVisibility: .visible) {
                Button("Remove all", role: .destructive) { lib.removeAll() }
            } message: {
                Text("You can download them again any time.")
            }
        }
        .preferredColorScheme(.dark)
    }
}
