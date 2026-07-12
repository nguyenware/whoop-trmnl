import Foundation

/// Loads and caches the bundled WHO/CDC LMS reference tables.
final class GrowthReferenceStore {
    static let shared = GrowthReferenceStore()

    private var cache: [String: GrowthDataset] = [:]
    private let lock = NSLock()

    private init() {}

    /// The reference table for a source/indicator/sex combination,
    /// or nil when that combination isn't published (e.g. CDC head
    /// circumference — the app uses WHO for 0–2 y as the CDC recommends).
    func dataset(source: GrowthSource, indicator: GrowthIndicator, sex: Sex) -> GrowthDataset? {
        let key = "\(source.rawValue)_\(indicator.rawValue)_\(sex.rawValue)"
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        guard let url = Bundle.main.url(forResource: key, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dataset = try? JSONDecoder().decode(GrowthDataset.self, from: data)
        else { return nil }
        cache[key] = dataset
        return dataset
    }

    /// The preferred source for an age, following clinical guidance:
    /// WHO standards for 0–24 months, CDC references from 2 years on.
    func recommendedSource(forAgeMonths age: Double) -> GrowthSource {
        age < 24 ? .who : .cdc
    }

    /// Sources that actually have data covering the given age.
    func availableSources(indicator: GrowthIndicator, sex: Sex, ageMonths: Double) -> [GrowthSource] {
        GrowthSource.allCases.filter { source in
            guard let ds = dataset(source: source, indicator: indicator, sex: sex) else { return false }
            return ds.xRange.contains(ageMonths)
        }
    }
}
