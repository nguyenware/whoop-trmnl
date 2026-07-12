import Foundation

/// The organization that published a growth reference.
enum GrowthSource: String, Codable, CaseIterable, Identifiable {
    case who
    case cdc

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .who: return "WHO"
        case .cdc: return "CDC"
        }
    }

    var longName: String {
        switch self {
        case .who: return "WHO Child Growth Standards"
        case .cdc: return "CDC Growth Charts (United States)"
        }
    }

    /// Percentile curves drawn on the official paper charts for this source.
    var standardPercentiles: [Double] {
        switch self {
        case .who: return [3, 15, 50, 85, 97]
        case .cdc: return [5, 10, 25, 50, 75, 90, 95]
        }
    }
}

/// What is being measured, and against what it is referenced.
enum GrowthIndicator: String, Codable, CaseIterable, Identifiable {
    case weightForAge
    case lengthHeightForAge
    case headCircumferenceForAge
    case bmiForAge
    case weightForLength
    case weightForHeight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weightForAge: return "Weight for Age"
        case .lengthHeightForAge: return "Height for Age"
        case .headCircumferenceForAge: return "Head Circumference"
        case .bmiForAge: return "BMI for Age"
        case .weightForLength: return "Weight for Length"
        case .weightForHeight: return "Weight for Height"
        }
    }

    var shortName: String {
        switch self {
        case .weightForAge: return "Weight"
        case .lengthHeightForAge: return "Height"
        case .headCircumferenceForAge: return "Head"
        case .bmiForAge: return "BMI"
        case .weightForLength: return "Wt/Len"
        case .weightForHeight: return "Wt/Ht"
        }
    }

    /// The measured (y-axis) quantity.
    var quantity: GrowthQuantity {
        switch self {
        case .weightForAge, .weightForLength, .weightForHeight: return .weight
        case .lengthHeightForAge: return .length
        case .headCircumferenceForAge: return .headCircumference
        case .bmiForAge: return .bmi
        }
    }

    /// Indicators plotted against age (the rest are plotted against length/height).
    var isAgeBased: Bool {
        switch self {
        case .weightForLength, .weightForHeight: return false
        default: return true
        }
    }
}

/// The physical quantity on a chart's y-axis.
enum GrowthQuantity {
    case weight            // kg
    case length            // cm
    case headCircumference // cm
    case bmi               // kg/m²
}

/// A single row of an LMS reference table.
struct LMSPoint: Codable {
    /// Age in months for age-based indicators; length/height in cm otherwise.
    let x: Double
    let l: Double
    let m: Double
    let s: Double
}

/// One reference table (e.g. WHO weight-for-age, boys).
struct GrowthDataset: Codable {
    let source: GrowthSource
    let indicator: GrowthIndicator
    let sex: Sex
    let xUnit: String
    let points: [LMSPoint]

    var xRange: ClosedRange<Double> {
        (points.first?.x ?? 0)...(points.last?.x ?? 0)
    }

    /// Linearly interpolated L, M, S parameters at `x`.
    /// Returns nil when `x` is outside the table's range.
    func lms(at x: Double) -> (l: Double, m: Double, s: Double)? {
        guard let first = points.first, let last = points.last,
              x >= first.x, x <= last.x else { return nil }
        // Binary search for the surrounding grid points.
        var lo = 0
        var hi = points.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if points[mid].x <= x { lo = mid } else { hi = mid }
        }
        let a = points[lo]
        let b = points[hi]
        guard b.x > a.x else { return (a.l, a.m, a.s) }
        let t = (x - a.x) / (b.x - a.x)
        return (a.l + t * (b.l - a.l),
                a.m + t * (b.m - a.m),
                a.s + t * (b.s - a.s))
    }

    /// Z-score of a measured value at position `x`, via the LMS method.
    func zScore(value: Double, at x: Double) -> Double? {
        guard value > 0, let p = lms(at: x) else { return nil }
        return LMSMath.zScore(value: value, l: p.l, m: p.m, s: p.s)
    }

    /// Exact percentile (0–100) of a measured value at position `x`.
    func percentile(value: Double, at x: Double) -> Double? {
        zScore(value: value, at: x).map { LMSMath.normalCDF($0) * 100 }
    }

    /// The measurement value lying on the given percentile curve at `x`.
    func value(percentile: Double, at x: Double) -> Double? {
        guard let p = lms(at: x) else { return nil }
        let z = LMSMath.normalQuantile(percentile / 100)
        return LMSMath.value(z: z, l: p.l, m: p.m, s: p.s)
    }
}
