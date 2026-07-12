import SwiftUI
import SwiftData

/// Plot several children on one chart to compare their growth.
struct CompareChildrenView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Child.createdAt) private var children: [Child]
    @AppStorage(SettingsKeys.unitSystem) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(SettingsKeys.useCorrectedAge) private var useCorrectedAge = true

    @State private var selectedIDs: Set<UUID> = []
    @State private var indicator: GrowthIndicator = .weightForAge

    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    private var selectedChildren: [Child] {
        children.filter { selectedIDs.contains($0.id) }
    }

    private var mixedSexes: Bool {
        Set(selectedChildren.map(\.sex)).count > 1
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Children") {
                    ForEach(children) { child in
                        Button {
                            toggle(child)
                        } label: {
                            HStack {
                                Text(child.name)
                                Spacer()
                                Text(child.ageDescription())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Image(systemName: selectedIDs.contains(child.id)
                                        ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    Picker("Chart", selection: $indicator) {
                        Text("Weight").tag(GrowthIndicator.weightForAge)
                        Text("Height").tag(GrowthIndicator.lengthHeightForAge)
                        Text("Head").tag(GrowthIndicator.headCircumferenceForAge)
                        Text("BMI").tag(GrowthIndicator.bmiForAge)
                    }
                    .pickerStyle(.segmented)

                    if selectedChildren.count < 2 {
                        Text("Select at least two children to compare.")
                            .foregroundStyle(.secondary)
                    } else if let model = GrowthChartModel.build(children: selectedChildren,
                                                                 indicator: indicator,
                                                                 preferredSource: nil,
                                                                 unitSystem: unitSystem,
                                                                 useCorrectedAge: useCorrectedAge,
                                                                 fitToData: true) {
                        GrowthChartView(model: model)
                            .frame(height: 360)
                            .padding(.vertical, 4)
                        if mixedSexes {
                            Text("Percentile curves are hidden when comparing boys and girls, because each sex has its own reference chart.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No measurements to plot yet.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Comparison")
                }
            }
            .navigationTitle("Compare Growth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if selectedIDs.isEmpty {
                    selectedIDs = Set(children.prefix(2).map(\.id))
                }
            }
        }
    }

    private func toggle(_ child: Child) {
        if selectedIDs.contains(child.id) {
            selectedIDs.remove(child.id)
        } else {
            selectedIDs.insert(child.id)
        }
    }
}
