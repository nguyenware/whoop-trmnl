import Foundation
import SwiftData

/// Average days per month used by the WHO/CDC reference tables.
let daysPerMonth = 30.4375

@Model
final class Child {
    var id: UUID = UUID()
    var name: String = ""
    var birthDate: Date = Date()
    /// Stored as a raw string because SwiftData persists it more robustly.
    var sexRaw: String = Sex.male.rawValue
    /// Original due date. Set for preterm children to enable corrected age.
    var dueDate: Date?
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \GrowthMeasurement.child)
    var measurements: [GrowthMeasurement]? = []

    init(name: String, birthDate: Date, sex: Sex, dueDate: Date? = nil) {
        self.id = UUID()
        self.name = name
        self.birthDate = birthDate
        self.sexRaw = sex.rawValue
        self.dueDate = dueDate
        self.createdAt = Date()
    }

    var sex: Sex {
        get { Sex(rawValue: sexRaw) ?? .male }
        set { sexRaw = newValue.rawValue }
    }

    var sortedMeasurements: [GrowthMeasurement] {
        (measurements ?? []).sorted { $0.date < $1.date }
    }

    /// Weeks the child was born before the due date (0 for term/unset).
    var prematurityWeeks: Double {
        guard let dueDate, dueDate > birthDate else { return 0 }
        return dueDate.timeIntervalSince(birthDate) / (7 * 24 * 3600)
    }

    /// Born 3+ weeks early.
    var isPreterm: Bool { prematurityWeeks >= 3 }

    /// Chronological age in months at a given date.
    func ageMonths(at date: Date) -> Double {
        date.timeIntervalSince(birthDate) / (daysPerMonth * 24 * 3600)
    }

    /// Age in months adjusted for prematurity, per standard practice
    /// (correct until 24 months corrected age, then use chronological).
    func correctedAgeMonths(at date: Date) -> Double {
        let chronological = ageMonths(at: date)
        guard isPreterm else { return chronological }
        let corrected = chronological - prematurityWeeks * 7 / daysPerMonth
        return corrected < 24 ? corrected : chronological
    }

    func ageMonths(at date: Date, corrected: Bool) -> Double {
        corrected ? correctedAgeMonths(at: date) : ageMonths(at: date)
    }

    /// Compact age description, e.g. "3 mo 12 d" or "4 yr 2 mo".
    func ageDescription(at date: Date = Date()) -> String {
        let cal = Calendar.current
        let parts = cal.dateComponents([.year, .month, .day], from: birthDate, to: date)
        let years = parts.year ?? 0
        let months = parts.month ?? 0
        let days = parts.day ?? 0
        if years >= 2 { return "\(years) yr \(months) mo" }
        let totalMonths = years * 12 + months
        if totalMonths >= 3 { return "\(totalMonths) mo" }
        if totalMonths >= 1 { return "\(totalMonths) mo \(days) d" }
        return "\(max(days, 0)) d"
    }
}
