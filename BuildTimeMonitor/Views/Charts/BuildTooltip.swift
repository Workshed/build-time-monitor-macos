import SwiftUI

/// Hover callout. Value leads; series is keyed with a short stroke, and all
/// text stays in primary/secondary ink rather than the series colour.
struct BuildTooltip: View {
    let point: DurationPoint
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Capsule().fill(color).frame(width: 12, height: 3)
                Text(point.series).font(.caption.weight(.semibold))
                if let build = point.build {
                    Text(build.scheme == point.series ? "" : build.scheme)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let build = point.build {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(DurationFormat.short(point.value))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    Text(build.kind.label.lowercased())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if build.isNoOp {
                        Text("no-op")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(build.plotDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                detailRow("arrow.triangle.branch", gitDescription(build))
                detailRow("gearshape", [build.configuration, build.sdk].filter { !$0.isEmpty }.joined(separator: " · "))
                if !build.xcodeVersion.isEmpty {
                    detailRow("hammer", "Xcode \(build.xcodeVersionDisplay)")
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(DurationFormat.short(point.value))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    Text("median")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(bucketTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(point.count) build\(point.count == 1 ? "" : "s") · \(DurationFormat.short(point.min))–\(DurationFormat.short(point.max))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .fixedSize()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
    }

    private var bucketTitle: String {
        switch point.bucket {
        case .weekOfYear?:
            "Week of " + point.date.formatted(.dateTime.day().month(.abbreviated))
        default:
            point.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
    }

    private func gitDescription(_ build: BuildRecord) -> String {
        switch (build.gitBranch.isEmpty, build.gitCommit.isEmpty) {
        case (false, false): "\(build.gitBranch) @ \(build.gitCommit)"
        case (false, true): build.gitBranch
        case (true, false): build.gitCommit
        case (true, true): ""
        }
    }

    @ViewBuilder
    private func detailRow(_ symbol: String, _ text: String) -> some View {
        if !text.isEmpty {
            Label(text, systemImage: symbol)
                .labelStyle(TooltipLabelStyle())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TooltipLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.frame(width: 12)
            configuration.title.lineLimit(1)
        }
    }
}
