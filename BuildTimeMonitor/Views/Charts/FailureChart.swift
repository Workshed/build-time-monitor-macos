import Charts
import SwiftUI

/// Failed/cancelled builds per bucket. Uses the reserved critical status colour;
/// the hover readout spells out the count, so colour never carries it alone.
struct FailureChart: View {
    let buckets: [FailureBucket]
    let range: TimeRange
    var height: CGFloat = 64

    @State private var hovered: FailureBucket?

    private var component: Calendar.Component { range.failureBucket }
    private var maxFailed: Int { max(buckets.map(\.failed).max() ?? 0, 1) }

    var body: some View {
        Chart {
            ForEach(buckets) { bucket in
                // Faint full-height track keeps empty periods visible and gives a big hover target.
                BarMark(
                    x: .value("Period", bucket.date, unit: component),
                    yStart: .value("Failed", 0),
                    yEnd: .value("Failed", maxFailed)
                )
                .foregroundStyle(ChartInk.gridline.opacity(hovered == bucket ? 1 : 0))
                .clipShape(RoundedRectangle(cornerRadius: 3))

                if bucket.failed > 0 {
                    BarMark(
                        x: .value("Period", bucket.date, unit: component),
                        y: .value("Failed", bucket.failed)
                    )
                    .foregroundStyle(StatusColor.critical.opacity(hovered == nil || hovered == bucket ? 1 : 0.45))
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3))
                }
            }
            if let hovered {
                RuleMark(x: .value("Period", hovered.date, unit: component))
                    .foregroundStyle(.clear)
                    .annotation(
                        position: .top,
                        spacing: 2,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        tooltip(for: hovered)
                    }
            }
        }
        .chartYScale(domain: 0...maxFailed)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisValueLabel(format: ChartAxes.dateFormat(for: range), centered: true)
                    .foregroundStyle(ChartInk.muted)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hovered = bucket(at: location, proxy: proxy, geometry: geometry)
                        case .ended:
                            hovered = nil
                        }
                    }
            }
        }
        .frame(height: height)
        .accessibilityLabel("Failed builds")
    }

    private func bucket(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> FailureBucket? {
        guard let plotFrame = proxy.plotFrame else { return nil }
        let x = location.x - geometry[plotFrame].origin.x
        guard let date: Date = proxy.value(atX: x) else { return nil }
        return buckets.last { $0.date <= date }
    }

    private func tooltip(for bucket: FailureBucket) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "xmark.octagon.fill").foregroundStyle(StatusColor.critical)
                Text("\(bucket.failed) failed").fontWeight(.semibold)
                Text("of \(bucket.total)").foregroundStyle(.secondary)
            }
            Text(title(for: bucket.date)).foregroundStyle(.secondary)
        }
        .font(.caption)
        .monospacedDigit()
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .fixedSize()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
    }

    private func title(for date: Date) -> String {
        switch component {
        case .hour: date.formatted(.dateTime.hour().minute())
        case .month: date.formatted(.dateTime.month(.wide).year())
        default: date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
    }
}
