import Foundation

/// Writes measurements (with computed percentiles) to a CSV file
/// suitable for spreadsheets or backups.
enum CSVExporter {

    static func export(children: [Child], useCorrectedAge: Bool) -> URL? {
        var rows: [String] = [
            "Child,Sex,Date of birth,Date,Age (months),Weight (kg),Height (cm),Head circumference (cm),BMI (kg/m2),Weight percentile,Height percentile,Head percentile,BMI percentile,Reference,Note"
        ]

        let dateFormat = Date.ISO8601FormatStyle(dateSeparator: .dash).year().month().day()

        for child in children {
            for m in child.sortedMeasurements {
                let results = GrowthAnalyzer.results(for: m, child: child,
                                                     useCorrectedAge: useCorrectedAge)
                func percentile(_ indicator: GrowthIndicator) -> String {
                    results.first { $0.indicator == indicator }
                        .map { String(format: "%.1f", $0.percentile) } ?? ""
                }
                let sources = Set(results.map { $0.source.displayName })
                let age = child.ageMonths(at: m.date, corrected: useCorrectedAge)

                let fields = [
                    csvEscape(child.name),
                    child.sex.displayName,
                    child.birthDate.formatted(dateFormat),
                    m.date.formatted(dateFormat),
                    String(format: "%.2f", age),
                    m.weightKg.map { String(format: "%.3f", $0) } ?? "",
                    m.heightCm.map { String(format: "%.1f", $0) } ?? "",
                    m.headCircumferenceCm.map { String(format: "%.1f", $0) } ?? "",
                    m.bmi.map { String(format: "%.2f", $0) } ?? "",
                    percentile(.weightForAge),
                    percentile(.lengthHeightForAge),
                    percentile(.headCircumferenceForAge),
                    percentile(.bmiForAge),
                    sources.sorted().joined(separator: "+"),
                    csvEscape(m.note),
                ]
                rows.append(fields.joined(separator: ","))
            }
        }

        let name = children.count == 1
            ? "\(safeFileName(children[0].name))-growth.csv"
            : "growth-data.csv"
        return writeExport(rows.joined(separator: "\n"), fileName: name)
    }

    static func csvEscape(_ field: String) -> String {
        if field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    static func safeFileName(_ name: String) -> String {
        let allowed = name.map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let result = String(allowed).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return result.isEmpty ? "child" : result
    }

    static func writeExport(_ content: String, fileName: String) -> URL? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(fileName)
        do {
            try content.data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
