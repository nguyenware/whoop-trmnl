import Foundation

/// A computed percentile for one indicator of one measurement.
struct PercentileResult: Identifiable {
    let indicator: GrowthIndicator
    let source: GrowthSource
    /// Measured value in metric units (kg, cm, or kg/m²).
    let value: Double
    let zScore: Double
    let percentile: Double

    var id: String { indicator.rawValue }
    var percentileLabel: String { LMSMath.percentileLabel(percentile) }
}

/// Turns raw measurements into percentiles against the right reference table.
enum GrowthAnalyzer {

    /// Percentiles for every indicator a measurement supports.
    /// - Parameters:
    ///   - source: force WHO or CDC; nil picks the recommended source for
    ///     the age (WHO under 2 years, CDC from 2 years) with fallback to
    ///     whichever covers the age.
    ///   - useCorrectedAge: plot preterm children at corrected age.
    static func results(for measurement: GrowthMeasurement,
                        child: Child,
                        source: GrowthSource? = nil,
                        useCorrectedAge: Bool = true) -> [PercentileResult] {
        let age = child.ageMonths(at: measurement.date, corrected: useCorrectedAge)
        guard age >= 0 else { return [] }
        var out: [PercentileResult] = []

        for indicator in GrowthIndicator.allCases {
            guard let value = measurement.value(for: indicator.quantity) else { continue }
            let x: Double
            if indicator.isAgeBased {
                x = age
            } else {
                // Weight-for-length/height uses the same-day length as x.
                guard let length = measurement.heightCm else { continue }
                // Show only the variant matching how the child is measured
                // (recumbent length under 2 y, standing height after).
                if indicator == .weightForLength && age >= 24 { continue }
                if indicator == .weightForHeight && age < 24 { continue }
                x = length
            }

            guard let (chosen, dataset) = resolveDataset(indicator: indicator,
                                                         sex: child.sex,
                                                         x: x,
                                                         preferred: source,
                                                         ageMonths: age)
            else { continue }
            guard let z = dataset.zScore(value: value, at: x) else { continue }
            out.append(PercentileResult(indicator: indicator,
                                        source: chosen,
                                        value: value,
                                        zScore: z,
                                        percentile: LMSMath.normalCDF(z) * 100))
        }
        return out
    }

    /// Picks a dataset that covers `x`, honoring a preferred source when it
    /// can, then the age-recommended source, then anything that fits.
    static func resolveDataset(indicator: GrowthIndicator,
                               sex: Sex,
                               x: Double,
                               preferred: GrowthSource?,
                               ageMonths: Double) -> (GrowthSource, GrowthDataset)? {
        let store = GrowthReferenceStore.shared
        var candidates: [GrowthSource] = []
        if let preferred { candidates.append(preferred) }
        let recommended = store.recommendedSource(forAgeMonths: ageMonths)
        candidates.append(recommended)
        candidates.append(contentsOf: GrowthSource.allCases)

        for source in candidates {
            if let ds = store.dataset(source: source, indicator: indicator, sex: sex),
               ds.xRange.contains(x) {
                return (source, ds)
            }
        }
        return nil
    }

    /// The most recent percentile per indicator across all measurements —
    /// what the child summary screen shows.
    static func latestResults(for child: Child,
                              useCorrectedAge: Bool = true) -> [PercentileResult] {
        var latest: [GrowthIndicator: PercentileResult] = [:]
        for measurement in child.sortedMeasurements {
            for result in results(for: measurement, child: child, useCorrectedAge: useCorrectedAge) {
                latest[result.indicator] = result
            }
        }
        return GrowthIndicator.allCases.compactMap { latest[$0] }
    }
}
