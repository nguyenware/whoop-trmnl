# Child Growth Tracker (iOS)

A SwiftUI iPhone/iPad app that plots your children's growth curves and computes
**exact percentiles** against the authoritative growth references:

- **WHO Child Growth Standards** (birth – 5 years, weekly resolution for the
  first 13 weeks)
- **CDC Growth Charts** (2 – 20 years, half-month resolution)

Percentiles and z-scores are computed with the **LMS method** (Cole), the same
method the WHO and CDC use to construct their charts — not read off a picture.

## Features

- **Multiple children** — track any number of profiles, each with its own
  measurement history; swipe to delete, tap to edit.
- **Compare** — plot several children together on one chart.
- **Indicators** — weight-for-age, length/height-for-age, head circumference,
  BMI-for-age (WHO and CDC), and weight-for-length / weight-for-height.
- **Exact percentiles & z-scores** for every measurement, with the reference
  (WHO/CDC) used shown next to each number.
- **Official chart ranges or custom fit** — view the full paper-chart range
  with the source's standard percentile curves (WHO: 3/15/50/85/97,
  CDC: 5/10/25/50/75/90/95), or auto-zoom to your child's data.
- **WHO ↔ CDC switching** — automatic per clinical guidance (WHO under
  2 years, CDC from 2–20), overridable per chart.
- **Preterm support** — record the original due date and charts use
  **corrected age** until 24 months (standard clinical practice).
- **Units** — metric (kg, cm) or US (lb + oz, ft + in), switchable at any
  time; data is stored metric and converted for display and entry.
- **Email / share charts** — render any chart to an image and share it.
- **CSV export** — per child or all children, including computed percentiles,
  for spreadsheets or backups.
- **PDF report & printing** — a multi-page report (profile, current
  percentiles, four charts, full measurement table) that can be shared,
  saved, or printed via AirPrint.
- **Device transfer / cloud backup** — full-fidelity JSON backup you can save
  to iCloud Drive (or any Files provider) and restore on another device.

## Project layout

```
ChildGrowthTracker/
├── ChildGrowthTracker.xcodeproj      Xcode 16 project (folder-synchronized)
└── ChildGrowthTracker/
    ├── ChildGrowthTrackerApp.swift   App entry, SwiftData container
    ├── Models/                       Child & GrowthMeasurement (@Model), units
    ├── GrowthEngine/                 LMS math, reference tables, analyzer
    ├── Views/                        SwiftUI screens and the Swift Charts view
    ├── Export/                       CSV, JSON backup, PDF report
    └── Resources/GrowthData/         18 bundled WHO/CDC LMS tables (JSON)
```

## Requirements & building

- Xcode 16 or newer (the project uses the folder-synchronized project format)
- iOS 17.0+ (SwiftData, Swift Charts, `ContentUnavailableView`)

Open `ChildGrowthTracker.xcodeproj`, select your signing team, and run.
There are no third-party dependencies.

## Reference data

The LMS tables in `Resources/GrowthData/` were converted from the WHO and CDC
tables bundled with the [pygrowup](https://pypi.org/project/pygrowup/) project
(WHO Child Growth Standards; CDC 2000 Growth Charts). The conversion merges
the WHO weekly tables (0–13 weeks) with the monthly tables (up to 60 months)
for better early-infancy precision, and the implementation was validated
against pygrowup's own z-score calculations.

**Not yet included:** the Fenton 2013 preterm charts. Redistribution of the
Fenton dataset requires permission from its authors, so preterm children are
supported via corrected age on the WHO charts (the standard post-discharge
approach). The growth engine is table-driven, so a licensed Fenton LMS table
can be dropped in as another JSON file later.

## Disclaimer

This app is for information only and is not a medical device. Always discuss
your child's growth with your pediatrician.
