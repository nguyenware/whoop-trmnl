import SwiftUI
import SwiftData

struct RootView: View {
    var body: some View {
        NavigationStack {
            ChildrenListView()
        }
    }
}

struct ChildrenListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Child.createdAt) private var children: [Child]
    @AppStorage(SettingsKeys.unitSystem) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(SettingsKeys.useCorrectedAge) private var useCorrectedAge = true

    @State private var showingAddChild = false
    @State private var showingSettings = false
    @State private var showingCompare = false

    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    var body: some View {
        Group {
            if children.isEmpty {
                ContentUnavailableView {
                    Label("No Children Yet", systemImage: "figure.and.child.holdinghands")
                } description: {
                    Text("Add your child to start tracking growth against WHO and CDC charts.")
                } actions: {
                    Button("Add Child") { showingAddChild = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(children) { child in
                        NavigationLink(value: child.id) {
                            ChildRow(child: child, unitSystem: unitSystem, useCorrectedAge: useCorrectedAge)
                        }
                    }
                    .onDelete(perform: deleteChildren)
                }
                .navigationDestination(for: UUID.self) { id in
                    if let child = children.first(where: { $0.id == id }) {
                        ChildDetailView(child: child)
                    }
                }
            }
        }
        .navigationTitle("Growth Tracker")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if children.count > 1 {
                    Button {
                        showingCompare = true
                    } label: {
                        Label("Compare", systemImage: "chart.xyaxis.line")
                    }
                }
                Button {
                    showingAddChild = true
                } label: {
                    Label("Add Child", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showingAddChild) {
            ChildFormView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingCompare) {
            CompareChildrenView()
        }
    }

    private func deleteChildren(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(children[index])
        }
    }
}

private struct ChildRow: View {
    let child: Child
    let unitSystem: UnitSystem
    let useCorrectedAge: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(child.name).font(.headline)
                if child.isPreterm {
                    Text("preterm")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.2), in: Capsule())
                }
            }
            Text("\(child.sex.displayName) · \(child.ageDescription())")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let summary = latestSummary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var latestSummary: String? {
        let results = GrowthAnalyzer.latestResults(for: child, useCorrectedAge: useCorrectedAge)
        guard !results.isEmpty else { return nil }
        return results
            .filter { $0.indicator.isAgeBased && $0.indicator != .bmiForAge }
            .map { "\($0.indicator.shortName) \($0.percentileLabel)" }
            .joined(separator: " · ")
    }
}
