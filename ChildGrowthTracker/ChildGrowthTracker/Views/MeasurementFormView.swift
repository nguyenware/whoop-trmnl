import SwiftUI
import SwiftData

/// Add or edit a measurement, entering values in the user's preferred units.
struct MeasurementFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.unitSystem) private var unitSystemRaw = UnitSystem.metric.rawValue

    let child: Child
    var measurementToEdit: GrowthMeasurement?

    @State private var date = Date()
    // Metric fields
    @State private var weightKgText = ""
    @State private var heightCmText = ""
    @State private var headCmText = ""
    // US fields
    @State private var weightLbText = ""
    @State private var weightOzText = ""
    @State private var heightFtText = ""
    @State private var heightInText = ""
    @State private var headInText = ""
    @State private var note = ""

    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, in: child.birthDate...Date(), displayedComponents: .date)
                    LabeledContent("Age", value: child.ageDescription(at: date))
                }

                Section("Weight") {
                    if unitSystem == .metric {
                        decimalField("Weight (kg)", text: $weightKgText)
                    } else {
                        HStack {
                            decimalField("Pounds", text: $weightLbText)
                            Divider()
                            decimalField("Ounces", text: $weightOzText)
                        }
                    }
                }

                Section(heightSectionTitle) {
                    if unitSystem == .metric {
                        decimalField("\(heightSectionTitle) (cm)", text: $heightCmText)
                    } else {
                        HStack {
                            decimalField("Feet", text: $heightFtText)
                            Divider()
                            decimalField("Inches", text: $heightInText)
                        }
                    }
                }

                Section("Head circumference") {
                    if unitSystem == .metric {
                        decimalField("Head circumference (cm)", text: $headCmText)
                    } else {
                        decimalField("Head circumference (in)", text: $headInText)
                    }
                }

                Section("Note") {
                    TextField("Optional note", text: $note, axis: .vertical)
                }

                if let bmi = enteredBMI {
                    Section {
                        LabeledContent("BMI", value: UnitFormat.bmi(bmi) + " kg/m²")
                    }
                }
            }
            .navigationTitle(measurementToEdit == nil ? "Add Measurement" : "Edit Measurement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!hasAnyValue)
                }
            }
            .onAppear(perform: populate)
        }
    }

    private var heightSectionTitle: String {
        child.ageMonths(at: date) < 24 ? "Length" : "Height"
    }

    private func decimalField(_ label: String, text: Binding<String>) -> some View {
        TextField(label, text: text)
            .keyboardType(.decimalPad)
    }

    // MARK: Parsing

    private func parse(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let v = Double(normalized), v >= 0 else { return nil }
        return v
    }

    private var enteredWeightKg: Double? {
        if unitSystem == .metric {
            return parse(weightKgText)
        }
        let lb = parse(weightLbText)
        let oz = parse(weightOzText)
        guard lb != nil || oz != nil else { return nil }
        return UnitConvert.kg(fromLb: lb ?? 0, oz: oz ?? 0)
    }

    private var enteredHeightCm: Double? {
        if unitSystem == .metric {
            return parse(heightCmText)
        }
        let ft = parse(heightFtText)
        let inches = parse(heightInText)
        guard ft != nil || inches != nil else { return nil }
        return UnitConvert.cm(fromFt: ft ?? 0, inches: inches ?? 0)
    }

    private var enteredHeadCm: Double? {
        if unitSystem == .metric {
            return parse(headCmText)
        }
        return parse(headInText).map(UnitConvert.cm(fromInches:))
    }

    private var enteredBMI: Double? {
        guard let w = enteredWeightKg, let h = enteredHeightCm, w > 0, h > 0 else { return nil }
        let meters = h / 100
        return w / (meters * meters)
    }

    private var hasAnyValue: Bool {
        (enteredWeightKg ?? 0) > 0 || (enteredHeightCm ?? 0) > 0 || (enteredHeadCm ?? 0) > 0
    }

    // MARK: Populate / save

    private func populate() {
        guard let m = measurementToEdit else { return }
        date = m.date
        note = m.note
        if let kg = m.weightKg {
            if unitSystem == .metric {
                weightKgText = String(format: "%.2f", kg)
            } else {
                let (lb, oz) = UnitConvert.lbOz(fromKg: kg)
                weightLbText = "\(lb)"
                weightOzText = String(format: "%.1f", oz)
            }
        }
        if let cm = m.heightCm {
            if unitSystem == .metric {
                heightCmText = String(format: "%.1f", cm)
            } else {
                let (ft, inches) = UnitConvert.ftIn(fromCm: cm)
                heightFtText = "\(ft)"
                heightInText = String(format: "%.1f", inches)
            }
        }
        if let cm = m.headCircumferenceCm {
            if unitSystem == .metric {
                headCmText = String(format: "%.1f", cm)
            } else {
                headInText = String(format: "%.2f", UnitConvert.inches(fromCm: cm))
            }
        }
    }

    private func save() {
        let weight = (enteredWeightKg ?? 0) > 0 ? enteredWeightKg : nil
        let height = (enteredHeightCm ?? 0) > 0 ? enteredHeightCm : nil
        let head = (enteredHeadCm ?? 0) > 0 ? enteredHeadCm : nil

        if let m = measurementToEdit {
            m.date = date
            m.weightKg = weight
            m.heightCm = height
            m.headCircumferenceCm = head
            m.note = note
        } else {
            let m = GrowthMeasurement(date: date,
                                      weightKg: weight,
                                      heightCm: height,
                                      headCircumferenceCm: head,
                                      note: note)
            m.child = child
            modelContext.insert(m)
        }
        dismiss()
    }
}
