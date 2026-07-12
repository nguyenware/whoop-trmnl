import SwiftUI
import SwiftData
import UIKit

struct ChildDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(SettingsKeys.unitSystem) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(SettingsKeys.useCorrectedAge) private var useCorrectedAge = true

    let child: Child

    @State private var showingAddMeasurement = false
    @State private var showingEditChild = false
    @State private var measurementToEdit: GrowthMeasurement?
    @State private var previewIndicator: GrowthIndicator = .weightForAge
    @State private var exportDocument: ExportedFile?

    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    var body: some View {
        List {
            headerSection
            percentileSection
            chartSection
            measurementsSection
        }
        .navigationTitle(child.name)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                exportMenu
                Button {
                    showingEditChild = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button {
                    showingAddMeasurement = true
                } label: {
                    Label("Add Measurement", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddMeasurement) {
            MeasurementFormView(child: child)
        }
        .sheet(isPresented: $showingEditChild) {
            ChildFormView(childToEdit: child)
        }
        .sheet(item: $measurementToEdit) { m in
            MeasurementFormView(child: child, measurementToEdit: m)
        }
        .sheet(item: $exportDocument) { doc in
            ShareSheet(items: [doc.url])
        }
    }

    // MARK: Sections

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(child.sex.displayName) · \(child.ageDescription())")
                    .font(.headline)
                Text("Born \(child.birthDate.formatted(date: .long, time: .omitted))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if child.isPreterm {
                    Text(String(format: "Preterm (%.0f weeks early) · corrected age %@",
                                child.prematurityWeeks,
                                correctedAgeText))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var correctedAgeText: String {
        let corrected = child.correctedAgeMonths(at: Date())
        if corrected < 0 { return "not yet due" }
        if corrected < 24 {
            return String(format: "%.1f mo", corrected)
        }
        return "no longer applied"
    }

    private var percentileSection: some View {
        Section("Current Percentiles") {
            let results = GrowthAnalyzer.latestResults(for: child, useCorrectedAge: useCorrectedAge)
            if results.isEmpty {
                Text("Add a measurement to see percentiles.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(results) { result in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(result.indicator.displayName)
                            Text(valueText(for: result))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(result.percentileLabel)
                                .font(.headline)
                                .foregroundStyle(percentileColor(result.percentile))
                            Text(String(format: "z %+.2f · %@", result.zScore, result.source.displayName))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func valueText(for result: PercentileResult) -> String {
        switch result.indicator.quantity {
        case .weight: return UnitFormat.weight(result.value, in: unitSystem)
        case .length: return UnitFormat.height(result.value, in: unitSystem)
        case .headCircumference: return UnitFormat.head(result.value, in: unitSystem)
        case .bmi: return UnitFormat.bmi(result.value) + " kg/m²"
        }
    }

    private func percentileColor(_ p: Double) -> Color {
        if p < 3 || p > 97 { return .red }
        if p < 10 || p > 90 { return .orange }
        return .primary
    }

    private var chartSection: some View {
        Section("Growth Chart") {
            Picker("Chart", selection: $previewIndicator) {
                ForEach(availableIndicators) { indicator in
                    Text(indicator.shortName).tag(indicator)
                }
            }
            .pickerStyle(.segmented)

            if let model = GrowthChartModel.build(children: [child],
                                                  indicator: previewIndicator,
                                                  preferredSource: nil,
                                                  unitSystem: unitSystem,
                                                  useCorrectedAge: useCorrectedAge,
                                                  fitToData: true) {
                GrowthChartView(model: model, showLegend: false)
                    .frame(height: 260)
                    .padding(.vertical, 4)
                NavigationLink {
                    ChartScreenView(child: child, initialIndicator: previewIndicator)
                } label: {
                    Label("Full Chart & Options", systemImage: "arrow.up.left.and.arrow.down.right")
                }
            } else {
                Text("Add measurements to see the chart.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var availableIndicators: [GrowthIndicator] {
        [.weightForAge, .lengthHeightForAge, .headCircumferenceForAge, .bmiForAge]
    }

    private var measurementsSection: some View {
        Section("Measurements") {
            let sorted = child.sortedMeasurements.reversed()
            if sorted.isEmpty {
                Text("No measurements yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(sorted)) { m in
                    Button {
                        measurementToEdit = m
                    } label: {
                        MeasurementRow(child: child, measurement: m,
                                       unitSystem: unitSystem, useCorrectedAge: useCorrectedAge)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    let items = Array(sorted)
                    for index in offsets {
                        modelContext.delete(items[index])
                    }
                }
            }
        }
    }

    // MARK: Export

    private var exportMenu: some View {
        Menu {
            Button {
                exportCSV()
            } label: {
                Label("Export CSV", systemImage: "tablecells")
            }
            Button {
                exportPDF()
            } label: {
                Label("Export PDF Report", systemImage: "doc.richtext")
            }
            Button {
                printPDF()
            } label: {
                Label("Print Report", systemImage: "printer")
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
    }

    private func exportCSV() {
        if let url = CSVExporter.export(children: [child], useCorrectedAge: useCorrectedAge) {
            exportDocument = ExportedFile(url: url)
        }
    }

    private func exportPDF() {
        if let url = PDFReportGenerator.report(for: child,
                                               unitSystem: unitSystem,
                                               useCorrectedAge: useCorrectedAge) {
            exportDocument = ExportedFile(url: url)
        }
    }

    private func printPDF() {
        guard let url = PDFReportGenerator.report(for: child,
                                                  unitSystem: unitSystem,
                                                  useCorrectedAge: useCorrectedAge) else { return }
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = "\(child.name) Growth Report"
        controller.printInfo = info
        controller.printingItem = url
        controller.present(animated: true)
    }
}

/// Identifiable wrapper so a file URL can drive a share sheet.
struct ExportedFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct MeasurementRow: View {
    let child: Child
    let measurement: GrowthMeasurement
    let unitSystem: UnitSystem
    let useCorrectedAge: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(measurement.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(child.ageDescription(at: measurement.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                if let kg = measurement.weightKg {
                    valueChip("scalemass", UnitFormat.weight(kg, in: unitSystem))
                }
                if let cm = measurement.heightCm {
                    valueChip("ruler", UnitFormat.height(cm, in: unitSystem))
                }
                if let head = measurement.headCircumferenceCm {
                    valueChip("circle.dashed", UnitFormat.head(head, in: unitSystem))
                }
            }
            let results = GrowthAnalyzer.results(for: measurement, child: child,
                                                 useCorrectedAge: useCorrectedAge)
            if !results.isEmpty {
                Text(results.map { "\($0.indicator.shortName) \($0.percentileLabel)" }
                        .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !measurement.note.isEmpty {
                Text(measurement.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
        .padding(.vertical, 2)
    }

    private func valueChip(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.caption2)
            Text(text).font(.caption)
        }
        .foregroundStyle(.primary)
    }
}
