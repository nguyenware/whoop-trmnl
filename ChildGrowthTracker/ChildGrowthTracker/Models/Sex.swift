import Foundation

enum Sex: String, Codable, CaseIterable, Identifiable {
    case male
    case female

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .male: return "Boy"
        case .female: return "Girl"
        }
    }

    var symbol: String {
        switch self {
        case .male: return "figure.child"
        case .female: return "figure.child"
        }
    }
}
