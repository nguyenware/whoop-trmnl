import SwiftUI
import Charts

// MARK: - Chart model

struct ChartXY {
    let x: Double
    let y: Double
}

struct ChartCurve: Identifiable {
    let id: String
    let label: String
    let isMedian: Bool
    let points: [ChartXY]
}

struct ChildChartSeries: Identifiable {
    let id: UUID
    let label: String
    let color: Color
    let points: [ChartXY]
}

/// Everything a growth chart needs, precomputed in display units.
struct GrowthChartModel {
    let indicator: GrowthIndicator
    let source: GrowthSource
    let unitSystem: UnitSystem
    let curves: [ChartCurve]
    let childSeries: [ChildChartSeries]
    let xDomain: ClosedRange<Double>
    let yDomain: ClosedRange<Double>
    let xIsAge: Bool

    static let seriesPalette: [Color] = [.blue, .pink, .green, .orange, .purple, .teal, .red, .indigo]

    var yAxisLabel: String {
        "\(indicator.shortName) (\(UnitFormat.chartUnitLabel(quantity: indicator.quantity, system: unitSystem)))"
    }

    var xAxisLabel: String {
        if xIsAge { return "Age" }
        let unit = unitSystem == .metric ? "cm" : "in"
        return "Length (\(unit))"
    }

    /// Tick positions with a stride that suits the visible span.
    var xAxisValues: [Double] {
        let span = xDomain.upperBound - xDomain.lowerBound
        let step: Double
        if xIsAge {
            switch span {
            case ..<7: step = 1
            case ..<15: step = 2
            case ..<25: step = 3
            case ..<49: step = 6
            case ..<121: step = 12
            default: step = 24
            }
        } else {
            let raw = span / 8
            step = max(1, (raw / 5).rounded() * 5) // multiples of 5 cm/in
        }
        let start = (xDomain.lowerBound / step).rounded(.up) * step
        return Array(stride(from: start, through: xDomain.upperBound, by: step))
    }

    func xTickLabel(_ x: Double) -> String {
        guard xIsAge else { return String(format: "%.0f", x) }
        let span = xDomain.upperBound - xDomain.lowerBound
        if span >= 48 {
            let years = x / 12
            return years == years.rounded() ? String(format: "%.0f y", years) : String(format: "%.1f y", years)
        }
        return String(format: "%.0f mo", x)
    }

    // MARK: Building

    /// - Parameters:
    ///   - children: one child, or several to compare.
    ///   - fitToData: zoom to the children's measurements ("custom fit")
    ///     instead of showing the full paper-chart range.
    static func build(children: [Child],
                      indicator: GrowthIndicator,
                      preferredSource: GrowthSource?,
                      unitSystem: UnitSystem,
                      useCorrectedAge: Bool,
                      fitToData: Bool) -> GrowthChartModel? {
        guard let firstChild = children.first else { return nil }

        // Percentile curves need a single reference table; pick it from the
        // first child's sex (callers only draw curves for same-sex groups)
        // and the age of the latest relevant measurement.
        let referenceAge = firstChild.sortedMeasurements.last.map {
            firstChild.ageMonths(at: $0.date, corrected: useCorrectedAge)
        } ?? 0

        let store = GrowthReferenceStore.shared
        var source = preferredSource ?? store.recommendedSource(forAgeMonths: referenceAge)
        var dataset = store.dataset(source: source, indicator: indicator, sex: firstChild.sex)
        if dataset == nil {
            // Preferred source doesn't publish this indicator; fall back.
            for alt in GrowthSource.allCases where alt != source {
                if let ds = store.dataset(source: alt, indicator: indicator, sex: firstChild.sex) {
                    source = alt
                    dataset = ds
                    break
                }
            }
        }
        guard let dataset else { return nil }

        let quantity = indicator.quantity
        let sameSex = children.allSatisfy { $0.sex == firstChild.sex }

        // Child data series (in display units).
        var series: [ChildChartSeries] = []
        for (index, child) in children.enumerated() {
            var pts: [ChartXY] = []
            for m in child.sortedMeasurements {
                guard let value = m.value(for: quantity) else { continue }
                let x: Double
                if indicator.isAgeBased {
                    x = child.ageMonths(at: m.date, corrected: useCorrectedAge)
                } else {
                    guard let len = m.heightCm else { continue }
                    x = unitSystem == .us ? UnitConvert.inches(fromCm: len) : len
                }
                guard x >= 0 else { continue }
                pts.append(ChartXY(x: x, y: UnitFormat.chartValue(value, quantity: quantity, system: unitSystem)))
            }
            guard !pts.isEmpty else { continue }
            series.append(ChildChartSeries(id: child.id,
                                           label: child.name,
                                           color: seriesPalette[index % seriesPalette.count],
                                           points: pts))
        }

        // X domain (dataset x is months or cm; convert cm → in for US).
        let xConvert: (Double) -> Double = { x in
            indicator.isAgeBased || unitSystem == .metric ? x : UnitConvert.inches(fromCm: x)
        }
        let fullRange = xConvert(dataset.xRange.lowerBound)...xConvert(dataset.xRange.upperBound)
        var xDomain = fullRange
        if fitToData {
            let xs = series.flatMap { $0.points.map(\.x) }
            if let lo = xs.min(), let hi = xs.max() {
                let minSpan = indicator.isAgeBased ? 4.0 : 10.0
                let pad = max(minSpan / 2, (hi - lo) * 0.15)
                var lower = max(fullRange.lowerBound, lo - pad)
                var upper = min(fullRange.upperBound, hi + pad)
                if upper - lower < minSpan {
                    let mid = (lower + upper) / 2
                    lower = max(fullRange.lowerBound, mid - minSpan / 2)
                    upper = min(fullRange.upperBound, mid + minSpan / 2)
                }
                // The measurements can sit entirely outside the reference's
                // range (e.g. CDC forced for an infant); keep a valid domain.
                if lower < upper {
                    xDomain = lower...upper
                }
            }
        }

        // Percentile curves across the visible domain (only meaningful when
        // every plotted child compares against the same reference).
        var curves: [ChartCurve] = []
        if sameSex {
            for p in source.standardPercentiles {
                var pts: [ChartXY] = []
                for point in dataset.points {
                    let x = xConvert(point.x)
                    guard xDomain.contains(x) else { continue }
                    if let v = dataset.value(percentile: p, at: point.x) {
                        pts.append(ChartXY(x: x, y: UnitFormat.chartValue(v, quantity: quantity, system: unitSystem)))
                    }
                }
                guard pts.count > 1 else { continue }
                curves.append(ChartCurve(id: "P\(p)",
                                         label: p == p.rounded() ? "P\(Int(p))" : "P\(p)",
                                         isMedian: p == 50,
                                         points: pts))
            }
        }

        // Y domain from everything visible.
        var ys = curves.flatMap { $0.points.map(\.y) }
        ys += series.flatMap { $0.points.filter { xDomain.contains($0.x) }.map(\.y) }
        guard let yLo = ys.min(), let yHi = ys.max() else { return nil }
        let yPad = max(0.5, (yHi - yLo) * 0.06)
        let yDomain = max(0, yLo - yPad)...(yHi + yPad)

        return GrowthChartModel(indicator: indicator,
                                source: source,
                                unitSystem: unitSystem,
                                curves: curves,
                                childSeries: series,
                                xDomain: xDomain,
                                yDomain: yDomain,
                                xIsAge: indicator.isAgeBased)
    }
}

// MARK: - Chart view

/// The growth chart itself: reference percentile curves + child data.
struct GrowthChartView: View {
    let model: GrowthChartModel
    var showLegend = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(model.curves) { curve in
                    ForEach(Array(curve.points.enumerated()), id: \.offset) { _, pt in
                        LineMark(x: .value(model.xAxisLabel, pt.x),
                                 y: .value(model.yAxisLabel, pt.y),
                                 series: .value("Series", curve.id))
                        .foregroundStyle(Color.secondary.opacity(curve.isMedian ? 0.85 : 0.4))
                        .lineStyle(StrokeStyle(lineWidth: curve.isMedian ? 1.6 : 1))
                    }
                    if let last = curve.points.last {
                        PointMark(x: .value(model.xAxisLabel, last.x),
                                  y: .value(model.yAxisLabel, last.y))
                        .symbolSize(0)
                        .annotation(position: .trailing, spacing: 2) {
                            Text(curve.label)
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(model.childSeries) { child in
                    ForEach(Array(child.points.enumerated()), id: \.offset) { _, pt in
                        LineMark(x: .value(model.xAxisLabel, pt.x),
                                 y: .value(model.yAxisLabel, pt.y),
                                 series: .value("Series", "child-\(child.id.uuidString)"))
                        .foregroundStyle(child.color)
                        .lineStyle(StrokeStyle(lineWidth: 2))

                        PointMark(x: .value(model.xAxisLabel, pt.x),
                                  y: .value(model.yAxisLabel, pt.y))
                        .foregroundStyle(child.color)
                        .symbolSize(28)
                    }
                }
            }
            .chartXScale(domain: model.xDomain)
            .chartYScale(domain: model.yDomain)
            .chartXAxis {
                AxisMarks(values: model.xAxisValues) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let x = value.as(Double.self) {
                            Text(model.xTickLabel(x))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 6))
            }
            .chartLegend(.hidden)

            if showLegend {
                legend
            }
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 12) {
                ForEach(model.childSeries) { child in
                    HStack(spacing: 4) {
                        Circle().fill(child.color).frame(width: 8, height: 8)
                        Text(child.label).font(.caption)
                    }
                }
            }
            Text("\(model.source.longName) · \(model.indicator.displayName)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
