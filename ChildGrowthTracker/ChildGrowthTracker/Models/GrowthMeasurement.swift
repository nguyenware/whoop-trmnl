import Foundation
import SwiftData

/// One measuring session. Any subset of the values may be recorded;
/// everything is stored metric and converted for display.
@Model
final class GrowthMeasurement {
    var id: UUID = UUID()
    var date: Date = Date()
    var weightKg: Double?
    var heightCm: Double?
    var headCircumferenceCm: Double?
    var note: String = ""
    var child: Child?

    init(date: Date,
         weightKg: Double? = nil,
         heightCm: Double? = nil,
         headCircumferenceCm: Double? = nil,
         note: String = "") {
        self.id = UUID()
        self.date = date
        self.weightKg = weightKg
        self.heightCm = heightCm
        self.headCircumferenceCm = headCircumferenceCm
        self.note = note
    }

    /// BMI in kg/m² when both weight and height were recorded.
    var bmi: Double? {
        guard let weightKg, let heightCm, heightCm > 0 else { return nil }
        let meters = heightCm / 100
        return weightKg / (meters * meters)
    }

    /// The stored value for a chart quantity.
    func value(for quantity: GrowthQuantity) -> Double? {
        switch quantity {
        case .weight: return weightKg
        case .length: return heightCm
        case .headCircumference: return headCircumferenceCm
        case .bmi: return bmi
        }
    }
}
