import Charts
import SwiftUI

struct DurationHistogram: View {
    let bins: [HistogramBin]
    let color: Color

    @State private var hovered: HistogramBin?

    var body: some View {
        Chart(bins) { bin in
            BarMark(
                xStart: .value("From", bin.lower),
                xEnd: .value("To", bin.upper),
                y: .value("Builds", bin.count)
            )
            .foregroundStyle(color.opacity(hovered == nil || hovered == bin ? 1 : 0.4))
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3))
            .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                if hovered == bin {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(bin.count) build\(bin.count == 1 ? "" : "s")").fontWeight(.semibold)
                        Text("\(DurationFormat.short(bin.lower))–\(DurationFormat.short(bin.upper))")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .fixedSize()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(DurationFormat.axis(seconds)).foregroundStyle(ChartInk.muted)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(ChartInk.gridline)
                AxisValueLabel().foregroundStyle(ChartInk.muted)
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
                            guard let plotFrame = proxy.plotFrame,
                                  let x: Double = proxy.value(atX: location.x - geometry[plotFrame].origin.x) else {
                                hovered = nil
                                return
                            }
                            hovered = bins.first { x >= $0.lower && x < $0.upper }
                        case .ended:
                            hovered = nil
                        }
                    }
            }
        }
    }
}
