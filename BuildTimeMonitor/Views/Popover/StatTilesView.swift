import SwiftUI

struct StatTile: View {
    let title: String
    let value: String
    var caption: String? = nil
    var symbol: String? = nil
    var symbolColor: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol)
                        .foregroundStyle(symbolColor ?? .secondary)
                        .imageScale(.small)
                }
                Text(title)
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.medium))

            Text(value)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(caption ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

struct StatTilesView: View {
    let summary: BuildSummary
    var columns = 2

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
                StatTile(
                    title: "Incremental",
                    value: DurationFormat.short(summary.averageIncremental),
                    caption: summary.incrementalCount == 0 ? "no builds" : "avg · median \(DurationFormat.short(summary.medianIncremental))",
                    symbol: "bolt.fill"
                )
                StatTile(
                    title: "Full",
                    value: DurationFormat.short(summary.averageFull),
                    caption: summary.fullCount == 0 ? "no builds" : "avg · \(summary.fullCount) build\(summary.fullCount == 1 ? "" : "s")",
                    symbol: "shippingbox.fill"
                )
                StatTile(
                    title: "Builds",
                    value: summary.buildCount.formatted(),
                    caption: "\(DurationFormat.total(summary.totalBuildTime)) spent building",
                    symbol: "hammer.fill"
                )
                StatTile(
                    title: "Failed",
                    value: summary.failedCount.formatted(),
                    caption: summary.buildCount == 0 ? "–" : "\(PercentFormat.string(summary.failureRate)) of builds",
                    symbol: "xmark.octagon.fill",
                    symbolColor: summary.failedCount > 0 ? StatusColor.critical : nil
                )
            }
        }
    }
}
