import SwiftUI
import SwiftData

/// Add or edit a child profile.
struct ChildFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var childToEdit: Child?

    @State private var name = ""
    @State private var sex: Sex = .male
    @State private var birthDate = Date()
    @State private var wasPreterm = false
    @State private var dueDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Child") {
                    TextField("Name", text: $name)
                    Picker("Sex", selection: $sex) {
                        ForEach(Sex.allCases) { s in
                            Text(s.displayName).tag(s)
                        }
                    }
                    DatePicker("Date of birth", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                }

                Section {
                    Toggle("Born preterm", isOn: $wasPreterm.animation())
                    if wasPreterm {
                        DatePicker("Original due date", selection: $dueDate, displayedComponents: .date)
                        if prematurityWeeks > 0 {
                            Text(String(format: "Born %.0f weeks early. Charts can use corrected age.", prematurityWeeks))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Prematurity")
                } footer: {
                    if wasPreterm {
                        Text("Corrected age is used on charts until 24 months, the standard clinical practice.")
                    }
                }
            }
            .navigationTitle(childToEdit == nil ? "Add Child" : "Edit Child")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: populate)
        }
    }

    private var prematurityWeeks: Double {
        guard wasPreterm, dueDate > birthDate else { return 0 }
        return dueDate.timeIntervalSince(birthDate) / (7 * 24 * 3600)
    }

    private func populate() {
        guard let child = childToEdit else { return }
        name = child.name
        sex = child.sex
        birthDate = child.birthDate
        if let due = child.dueDate {
            wasPreterm = true
            dueDate = due
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let child = childToEdit {
            child.name = trimmed
            child.sex = sex
            child.birthDate = birthDate
            child.dueDate = wasPreterm ? dueDate : nil
        } else {
            let child = Child(name: trimmed,
                              birthDate: birthDate,
                              sex: sex,
                              dueDate: wasPreterm ? dueDate : nil)
            modelContext.insert(child)
        }
        dismiss()
    }
}
