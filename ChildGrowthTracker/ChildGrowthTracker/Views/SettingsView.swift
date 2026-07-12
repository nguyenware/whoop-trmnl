import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Child.createdAt) private var children: [Child]

    @AppStorage(SettingsKeys.unitSystem) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(SettingsKeys.useCorrectedAge) private var useCorrectedAge = true

    @State private var exportDocument: ExportedFile?
    @State private var showingImporter = false
    @State private var importMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Measurement units", selection: $unitSystemRaw) {
                        ForEach(UnitSystem.allCases) { system in
                            Text(system.displayName).tag(system.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    Toggle("Use corrected age for preterm children", isOn: $useCorrectedAge)
                } footer: {
                    Text("Plots preterm children at their corrected age (chronological age minus weeks born early) until 24 months.")
                }

                Section {
                    Button {
                        exportAllCSV()
                    } label: {
                        Label("Export all data as CSV", systemImage: "tablecells")
                    }
                    Button {
                        exportBackup()
                    } label: {
                        Label("Back up data (JSON)", systemImage: "arrow.up.doc")
                    }
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Restore from backup", systemImage: "arrow.down.doc")
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Save the backup file to iCloud Drive or another cloud service to sync between devices, or share it to move your data to a new device. Restoring adds the children from the file alongside existing ones.")
                }

                Section("About the charts") {
                    Text("Percentiles are computed with the LMS method from the WHO Child Growth Standards (birth to 5 years) and the CDC Growth Charts (2 to 20 years). Following CDC guidance, WHO standards are used under age 2 and CDC references from age 2 by default.")
                        .font(.footnote)
                    Text("This app is for information only and is not a medical device. Discuss your child's growth with your pediatrician.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $exportDocument) { doc in
                ShareSheet(items: [doc.url])
            }
            .fileImporter(isPresented: $showingImporter,
                          allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    importBackup(from: url)
                case .failure(let error):
                    importMessage = "Import failed: \(error.localizedDescription)"
                }
            }
            .alert("Restore", isPresented: .init(get: { importMessage != nil },
                                                 set: { if !$0 { importMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importMessage ?? "")
            }
        }
    }

    private func exportAllCSV() {
        if let url = CSVExporter.export(children: children, useCorrectedAge: useCorrectedAge) {
            exportDocument = ExportedFile(url: url)
        }
    }

    private func exportBackup() {
        if let url = BackupService.exportBackup(children: children) {
            exportDocument = ExportedFile(url: url)
        }
    }

    private func importBackup(from url: URL) {
        do {
            let count = try BackupService.importBackup(from: url, into: modelContext)
            importMessage = "Restored \(count) child\(count == 1 ? "" : "ren") from backup."
        } catch {
            importMessage = "Import failed: \(error.localizedDescription)"
        }
    }
}
