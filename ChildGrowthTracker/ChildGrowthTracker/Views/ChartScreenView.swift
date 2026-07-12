import SwiftUI

/// Full-screen chart with source/fit/corrected-age controls and image export.
struct ChartScreenView: View {
    @AppStorage(SettingsKeys.unitSystem) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(SettingsKeys.useCorrectedAge) private var useCorrectedAgeDefault = true

    let child: Child
    var initialIndicator: GrowthIndicator = .weightForAge

    @State private var indicator: GrowthIndicator = .weightForAge
    @State private var sourceChoice: SourceChoice = .auto
    @State private var fitToData = true
    @State private var correctedAge = true
    @State private var appeared = false

    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    enum SourceChoice: String, CaseIterable, Identifiable {
        case auto, who, cdc
        var id: String { rawValue }
        var label: String {
            switch self {
            case .auto: return "Auto"
            case .who: return "WHO"
            case .cdc: return "CDC"
            }
        }
        var source: GrowthSource? {
            switch self {
            case .auto: return nil
            case .who: return .who
            case .cdc: return .cdc
            }
        }
    }

    private var model: GrowthChartModel? {
        GrowthChartModel.build(children: [child],
                               indicator: indicator,
                               preferredSource: sourceChoice.source,
                               unitSystem: unitSystem,
                               useCorrectedAge: correctedAge,
                               fitToData: fitToData)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Indicator", selection: $indicator) {
                    ForEach(chartIndicators) { ind in
                        Text(ind.displayName).tag(ind)
                    }
                }
                .pickerStyle(.menu)

                if let model {
                    GrowthChartView(model: model)
                        .frame(height: 420)
                } else {
                    ContentUnavailableView("No chart available",
                                           systemImage: "chart.line.uptrend.xyaxis",
                                           description: Text("No reference data covers this child's measurements for the selected chart."))
                        .frame(height: 300)
                }

                controls
            }
            .padding()
        }
        .navigationTitle(indicator.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let model {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: renderImage(model: model),
                              preview: SharePreview("\(child.name) – \(indicator.displayName)",
                                                    image: renderImage(model: model))) {
                        Label("Share Chart", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .onAppear {
            guard !appeared else { return }
            appeared = true
            indicator = initialIndicator
            correctedAge = useCorrectedAgeDefault && child.isPreterm
        }
    }

    private var chartIndicators: [GrowthIndicator] {
        var list: [GrowthIndicator] = [.weightForAge, .lengthHeightForAge,
                                       .headCircumferenceForAge, .bmiForAge]
        let latestAge = child.sortedMeasurements.last.map { child.ageMonths(at: $0.date) } ?? 0
        list.append(latestAge < 24 ? .weightForLength : .weightForHeight)
        return list
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Reference", selection: $sourceChoice) {
                ForEach(SourceChoice.allCases) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Fit chart to measurements", isOn: $fitToData)

            if child.isPreterm {
                Toggle("Use corrected age", isOn: $correctedAge)
            }

            if let model {
                Text(sourceFootnote(model: model))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private func sourceFootnote(model: GrowthChartModel) -> String {
        var text = "Reference: \(model.source.longName)."
        if sourceChoice == .auto {
            text += " Auto selects WHO under 2 years and CDC from 2 to 20 years."
        }
        if child.isPreterm && correctedAge {
            text += " Ages are corrected for prematurity until 24 months."
        }
        return text
    }

    /// Renders the chart to an image for sharing (email, save, AirDrop).
    @MainActor
    private func renderImage(model: GrowthChartModel) -> Image {
        let view = GrowthChartView(model: model)
            .frame(width: 700, height: 500)
            .padding()
            .background(Color.white)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let uiImage = renderer.uiImage {
            return Image(uiImage: uiImage)
        }
        return Image(systemName: "chart.line.uptrend.xyaxis")
    }
}
