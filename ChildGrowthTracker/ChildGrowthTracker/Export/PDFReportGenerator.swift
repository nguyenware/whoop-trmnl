import SwiftUI
import UIKit

/// Builds a printable PDF growth report: child details, growth charts,
/// and the full measurement table with percentiles.
enum PDFReportGenerator {

    private static let pageSize = CGSize(width: 612, height: 792) // US Letter
    private static let margin: CGFloat = 40

    @MainActor
    static func report(for child: Child, unitSystem: UnitSystem, useCorrectedAge: Bool) -> URL? {
        let chartIndicators: [GrowthIndicator] = [.weightForAge, .lengthHeightForAge,
                                                  .headCircumferenceForAge, .bmiForAge]
        // Render chart images up front (SwiftUI work must happen on the main actor).
        var chartImages: [(GrowthIndicator, UIImage)] = []
        for indicator in chartIndicators {
            guard let model = GrowthChartModel.build(children: [child],
                                                     indicator: indicator,
                                                     preferredSource: nil,
                                                     unitSystem: unitSystem,
                                                     useCorrectedAge: useCorrectedAge,
                                                     fitToData: true) else { continue }
            let view = GrowthChartView(model: model)
                .frame(width: 520, height: 340)
                .padding(8)
                .background(Color.white)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let image = renderer.uiImage {
                chartImages.append((indicator, image))
            }
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Exports", isDirectory: true)
            .appendingPathComponent("\(CSVExporter.safeFileName(child.name))-growth-report.pdf")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)

        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize),
                                             format: format)
        do {
            try renderer.writePDF(to: url) { ctx in
                var cursorY = startPage(ctx)

                // Header
                cursorY = draw(text: "\(child.name) — Growth Report",
                               font: .boldSystemFont(ofSize: 22), at: cursorY, in: ctx)
                var subtitle = "\(child.sex.displayName) · born \(child.birthDate.formatted(date: .long, time: .omitted)) · age \(child.ageDescription())"
                if child.isPreterm {
                    subtitle += String(format: " · preterm (%.0f wk early)", child.prematurityWeeks)
                }
                cursorY = draw(text: subtitle, font: .systemFont(ofSize: 11),
                               color: .darkGray, at: cursorY + 4, in: ctx)
                cursorY = draw(text: "Generated \(Date().formatted(date: .abbreviated, time: .shortened)) · WHO Child Growth Standards / CDC Growth Charts (LMS method)",
                               font: .systemFont(ofSize: 9), color: .gray,
                               at: cursorY + 2, in: ctx)
                cursorY += 10

                // Latest percentiles
                let latest = GrowthAnalyzer.latestResults(for: child, useCorrectedAge: useCorrectedAge)
                if !latest.isEmpty {
                    cursorY = draw(text: "Current percentiles", font: .boldSystemFont(ofSize: 13),
                                   at: cursorY, in: ctx)
                    for result in latest {
                        let line = "\(result.indicator.displayName): \(valueText(result, unitSystem: unitSystem))  →  \(result.percentileLabel) (z \(String(format: "%+.2f", result.zScore)), \(result.source.displayName))"
                        cursorY = draw(text: line, font: .systemFont(ofSize: 10),
                                       at: cursorY + 2, in: ctx)
                    }
                    cursorY += 8
                }

                // Charts, two per page as they fit
                for (indicator, image) in chartImages {
                    let drawWidth = pageSize.width - margin * 2
                    let drawHeight = drawWidth * image.size.height / image.size.width
                    if cursorY + drawHeight + 20 > pageSize.height - margin {
                        cursorY = startPage(ctx)
                    }
                    cursorY = draw(text: indicator.displayName, font: .boldSystemFont(ofSize: 13),
                                   at: cursorY, in: ctx)
                    image.draw(in: CGRect(x: margin, y: cursorY + 4,
                                          width: drawWidth, height: drawHeight))
                    cursorY += drawHeight + 16
                }

                // Measurement table
                cursorY = startPage(ctx)
                cursorY = draw(text: "Measurements", font: .boldSystemFont(ofSize: 15),
                               at: cursorY, in: ctx)
                cursorY += 6
                cursorY = drawTableHeader(at: cursorY, in: ctx)
                for m in child.sortedMeasurements {
                    if cursorY + 16 > pageSize.height - margin {
                        cursorY = startPage(ctx)
                        cursorY = drawTableHeader(at: cursorY, in: ctx)
                    }
                    cursorY = drawTableRow(for: m, child: child, unitSystem: unitSystem,
                                           useCorrectedAge: useCorrectedAge, at: cursorY, in: ctx)
                }
            }
            return url
        } catch {
            return nil
        }
    }

    // MARK: Drawing helpers

    private static func startPage(_ ctx: UIGraphicsPDFRendererContext) -> CGFloat {
        ctx.beginPage()
        return margin
    }

    @discardableResult
    private static func draw(text: String,
                             font: UIFont,
                             color: UIColor = .black,
                             at y: CGFloat,
                             in ctx: UIGraphicsPDFRendererContext) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let bounds = CGRect(x: margin, y: y,
                            width: pageSize.width - margin * 2,
                            height: .greatestFiniteMagnitude)
        let size = (text as NSString).boundingRect(with: bounds.size,
                                                   options: [.usesLineFragmentOrigin],
                                                   attributes: attributes,
                                                   context: nil).size
        (text as NSString).draw(with: CGRect(origin: bounds.origin, size: size),
                                options: [.usesLineFragmentOrigin],
                                attributes: attributes,
                                context: nil)
        return y + size.height
    }

    private static let columns: [(title: String, x: CGFloat, width: CGFloat)] = [
        ("Date", 40, 70),
        ("Age", 112, 55),
        ("Weight", 169, 78),
        ("Height", 249, 72),
        ("Head", 323, 62),
        ("BMI", 387, 40),
        ("Percentiles (Wt/Ht/Head/BMI)", 429, 145),
    ]

    private static func drawTableHeader(at y: CGFloat,
                                        in ctx: UIGraphicsPDFRendererContext) -> CGFloat {
        let font = UIFont.boldSystemFont(ofSize: 8.5)
        for col in columns {
            (col.title as NSString).draw(in: CGRect(x: col.x, y: y, width: col.width, height: 12),
                                         withAttributes: [.font: font])
        }
        let line = UIBezierPath()
        line.move(to: CGPoint(x: margin, y: y + 13))
        line.addLine(to: CGPoint(x: pageSize.width - margin, y: y + 13))
        UIColor.lightGray.setStroke()
        line.lineWidth = 0.5
        line.stroke()
        return y + 17
    }

    private static func drawTableRow(for m: GrowthMeasurement,
                                     child: Child,
                                     unitSystem: UnitSystem,
                                     useCorrectedAge: Bool,
                                     at y: CGFloat,
                                     in ctx: UIGraphicsPDFRendererContext) -> CGFloat {
        let results = GrowthAnalyzer.results(for: m, child: child, useCorrectedAge: useCorrectedAge)
        func pct(_ indicator: GrowthIndicator) -> String {
            results.first { $0.indicator == indicator }.map { LMSMath.percentileLabel($0.percentile) } ?? "–"
        }
        let values: [String] = [
            m.date.formatted(date: .numeric, time: .omitted),
            child.ageDescription(at: m.date),
            m.weightKg.map { UnitFormat.weight($0, in: unitSystem) } ?? "–",
            m.heightCm.map { UnitFormat.height($0, in: unitSystem) } ?? "–",
            m.headCircumferenceCm.map { UnitFormat.head($0, in: unitSystem) } ?? "–",
            m.bmi.map { UnitFormat.bmi($0) } ?? "–",
            "\(pct(.weightForAge)) / \(pct(.lengthHeightForAge)) / \(pct(.headCircumferenceForAge)) / \(pct(.bmiForAge))",
        ]
        let font = UIFont.systemFont(ofSize: 8.5)
        for (col, value) in zip(columns, values) {
            (value as NSString).draw(in: CGRect(x: col.x, y: y, width: col.width, height: 12),
                                     withAttributes: [.font: font])
        }
        return y + 14
    }

    private static func valueText(_ result: PercentileResult, unitSystem: UnitSystem) -> String {
        switch result.indicator.quantity {
        case .weight: return UnitFormat.weight(result.value, in: unitSystem)
        case .length: return UnitFormat.height(result.value, in: unitSystem)
        case .headCircumference: return UnitFormat.head(result.value, in: unitSystem)
        case .bmi: return UnitFormat.bmi(result.value) + " kg/m²"
        }
    }
}
