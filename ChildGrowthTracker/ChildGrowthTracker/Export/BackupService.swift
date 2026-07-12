import Foundation
import SwiftData

/// Full-fidelity JSON backup, for device transfer and cloud storage.
enum BackupService {

    struct Backup: Codable {
        var version = 1
        var exportedAt = Date()
        var children: [ChildRecord] = []
    }

    struct ChildRecord: Codable {
        var name: String
        var birthDate: Date
        var sex: Sex
        var dueDate: Date?
        var measurements: [MeasurementRecord]
    }

    struct MeasurementRecord: Codable {
        var date: Date
        var weightKg: Double?
        var heightCm: Double?
        var headCircumferenceCm: Double?
        var note: String
    }

    static func exportBackup(children: [Child]) -> URL? {
        var backup = Backup()
        backup.children = children.map { child in
            ChildRecord(name: child.name,
                        birthDate: child.birthDate,
                        sex: child.sex,
                        dueDate: child.dueDate,
                        measurements: child.sortedMeasurements.map { m in
                            MeasurementRecord(date: m.date,
                                              weightKg: m.weightKg,
                                              heightCm: m.heightCm,
                                              headCircumferenceCm: m.headCircumferenceCm,
                                              note: m.note)
                        })
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(backup),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return CSVExporter.writeExport(text, fileName: "growth-tracker-backup.json")
    }

    /// Imports children from a backup file. Returns the number added.
    static func importBackup(from url: URL, into context: ModelContext) throws -> Int {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(Backup.self, from: data)

        for record in backup.children {
            let child = Child(name: record.name,
                              birthDate: record.birthDate,
                              sex: record.sex,
                              dueDate: record.dueDate)
            context.insert(child)
            for m in record.measurements {
                let measurement = GrowthMeasurement(date: m.date,
                                                    weightKg: m.weightKg,
                                                    heightCm: m.heightCm,
                                                    headCircumferenceCm: m.headCircumferenceCm,
                                                    note: m.note)
                measurement.child = child
                context.insert(measurement)
            }
        }
        return backup.children.count
    }
}
