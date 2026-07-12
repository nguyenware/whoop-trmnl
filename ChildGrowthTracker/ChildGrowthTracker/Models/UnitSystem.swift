import Foundation

/// Display units. All values are stored metric; conversion happens at the UI.
enum UnitSystem: String, CaseIterable, Identifiable {
    case metric
    case us

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .metric: return "Metric (kg, cm)"
        case .us: return "US (lb, oz, ft, in)"
        }
    }
}

enum UnitConvert {
    static let kgPerLb = 0.45359237
    static let cmPerInch = 2.54

    static func lb(fromKg kg: Double) -> Double { kg / kgPerLb }
    static func kg(fromLb lb: Double) -> Double { lb * kgPerLb }
    static func inches(fromCm cm: Double) -> Double { cm / cmPerInch }
    static func cm(fromInches inches: Double) -> Double { inches * cmPerInch }

    /// Whole pounds and remaining ounces, e.g. 3.4 kg → (7 lb, 8 oz).
    static func lbOz(fromKg kg: Double) -> (lb: Int, oz: Double) {
        let totalOz = lb(fromKg: kg) * 16
        var lbPart = Int(totalOz / 16)
        var ozPart = totalOz - Double(lbPart) * 16
        if ozPart > 15.95 { lbPart += 1; ozPart = 0 }
        return (lbPart, ozPart)
    }

    static func kg(fromLb lb: Double, oz: Double) -> Double {
        kg(fromLb: lb + oz / 16)
    }

    /// Whole feet and remaining inches, e.g. 96.5 cm → (3 ft, 2.0 in).
    static func ftIn(fromCm cm: Double) -> (ft: Int, inches: Double) {
        let totalIn = inches(fromCm: cm)
        var ftPart = Int(totalIn / 12)
        var inPart = totalIn - Double(ftPart) * 12
        if inPart > 11.95 { ftPart += 1; inPart = 0 }
        return (ftPart, inPart)
    }

    static func cm(fromFt ft: Double, inches: Double) -> Double {
        cm(fromInches: ft * 12 + inches)
    }
}

/// Formatting of stored metric values in the user's chosen units.
enum UnitFormat {
    static func weight(_ kg: Double, in system: UnitSystem) -> String {
        switch system {
        case .metric:
            return String(format: "%.2f kg", kg)
        case .us:
            let (lb, oz) = UnitConvert.lbOz(fromKg: kg)
            return String(format: "%d lb %.1f oz", lb, oz)
        }
    }

    static func height(_ cm: Double, in system: UnitSystem) -> String {
        switch system {
        case .metric:
            return String(format: "%.1f cm", cm)
        case .us:
            let inches = UnitConvert.inches(fromCm: cm)
            if inches >= 36 {
                let (ft, inPart) = UnitConvert.ftIn(fromCm: cm)
                return String(format: "%d ft %.1f in", ft, inPart)
            }
            return String(format: "%.1f in", inches)
        }
    }

    static func head(_ cm: Double, in system: UnitSystem) -> String {
        switch system {
        case .metric:
            return String(format: "%.1f cm", cm)
        case .us:
            return String(format: "%.2f in", UnitConvert.inches(fromCm: cm))
        }
    }

    static func bmi(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    /// Value converted for chart axes (kept decimal — lb/in on charts).
    static func chartValue(_ metricValue: Double, quantity: GrowthQuantity, system: UnitSystem) -> Double {
        guard system == .us else { return metricValue }
        switch quantity {
        case .weight: return UnitConvert.lb(fromKg: metricValue)
        case .length, .headCircumference: return UnitConvert.inches(fromCm: metricValue)
        case .bmi: return metricValue
        }
    }

    static func chartUnitLabel(quantity: GrowthQuantity, system: UnitSystem) -> String {
        switch quantity {
        case .weight: return system == .metric ? "kg" : "lb"
        case .length, .headCircumference: return system == .metric ? "cm" : "in"
        case .bmi: return "kg/m²"
        }
    }
}
