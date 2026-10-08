import Charts
import SwiftUI

/// Line chart of build durations, one line per project, with a hover
/// crosshair that snaps to the nearest point and shows a detail callout.
struct BuildDurationChart: View {
    let points: [DurationPoint]
    let projects: [String]
    let range: TimeRange
    let domain: DateInterval
    var showsLegend = true
    var compact = true

    @State private var hovered: DurationPoint?

    private var seriesDomain: [String] { ProjectPalette.seriesDomain(for: projects) }
    private var isAggregated: Bool { points.first?.bucket != nil }
    private var trend: [TrendPoint] { isAggregated ? [] : BuildStats.trend(points) }
    private var yTicks: [TimeInterval] {
        ChartAxes.durationTicks(maxValue: points.map(\.value).max() ?? 60, targetCount: compact ? 4 : 6)
    }

    var body: some View {
        Chart {
            if isAggregated {
                // Bucket medians: a line through each bucket with a marker per bucket.
                ForEach(points) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Duration", point.value),
                        series: .value("Project", point.series)
                    )
                    .foregroundStyle(by: .value("Project", point.series))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)

                    PointMark(x: .value("Time", point.date), y: .value("Duration", point.value))
                        .foregroundStyle(by: .value("Project", point.series))
                        .symbolSize(compact ? 18 : 26)
                }
            } else {
                // Individual builds as dots, with a rolling-median trend line per project.
                ForEach(points) { point in
                    PointMark(x: .value("Time", point.date), y: .value("Duration", point.value))
                        .foregroundStyle(by: .value("Project", point.series))
                        .symbolSize(compact ? 14 : 20)
                        .opacity(hovered == nil ? 0.45 : 0.25)
                }
                ForEach(trend) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Median", point.value),
                        series: .value("Project", point.series)
                    )
                    .foregroundStyle(by: .value("Project", point.series))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                }
            }

            if let hovered {
                RuleMark(x: .value("Time", hovered.date))
                    .foregroundStyle(ChartInk.baseline)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .zIndex(-1)

                // Surface ring first, then the marker, so it lifts off the line.
                PointMark(x: .value("Time", hovered.date), y: .value("Duration", hovered.value))
                    .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                    .symbolSize(compact ? 150 : 190)
                PointMark(x: .value("Time", hovered.date), y: .value("Duration", hovered.value))
                    .foregroundStyle(ProjectPalette.color(for: hovered.series, in: projects))
                    .symbolSize(compact ? 70 : 90)
                    .annotation(
                        position: .top,
                        spacing: 8,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        BuildTooltip(point: hovered, color: ProjectPalette.color(for: hovered.series, in: projects))
                    }
            }
        }
        .chartForegroundStyleScale(domain: seriesDomain, range: ProjectPalette.colors(for: projects))
        .chartLegend(showsLegend && seriesDomain.count > 1 ? .visible : .hidden)
        .chartLegend(position: .bottom, alignment: .leading, spacing: 10)
        .chartXScale(domain: domain.start...domain.end)
        .chartYScale(domain: 0...(yTicks.last ?? 60))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: compact ? 5 : 8)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(ChartInk.gridline)
                AxisTick(length: 3).foregroundStyle(ChartInk.baseline)
                AxisValueLabel(format: ChartAxes.dateFormat(for: range))
                    .foregroundStyle(ChartInk.muted)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: yTicks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(ChartInk.gridline)
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(DurationFormat.axis(seconds))
                            .monospacedDigit()
                            .foregroundStyle(ChartInk.muted)
                    }
                }
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
                            hovered = nearestPoint(to: location, proxy: proxy, geometry: geometry)
                        case .ended:
                            hovered = nil
                        }
                    }
            }
        }
        .animation(.snappy(duration: 0.15), value: hovered)
        #if DEBUG
        .onAppear {
            // `-PreviewHover YES` pins a hovered point for screenshots.
            if UserDefaults.standard.bool(forKey: "PreviewHover"), !points.isEmpty {
                hovered = points.sorted { $0.date < $1.date }[points.count * 3 / 4]
            }
        }
        #endif
        .accessibilityLabel("Build durations")
    }

    /// Nearest point in screen space, so hovering near a line picks that line
    /// even when another project built at a similar time.
    private func nearestPoint(to location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> DurationPoint? {
        guard let plotFrame = proxy.plotFrame else { return nil }
        let origin = geometry[plotFrame].origin
        let local = CGPoint(x: location.x - origin.x, y: location.y - origin.y)
        var best: (point: DurationPoint, distance: CGFloat)?
        for point in points {
            guard let position = proxy.position(for: (x: point.date, y: point.value)) else { continue }
            // Weight horizontal distance more: people scrub along time.
            let dx = position.x - local.x
            let dy = (position.y - local.y) * 0.5
            let distance = dx * dx + dy * dy
            if distance < (best?.distance ?? .infinity) {
                best = (point, distance)
            }
        }
        guard let best, best.distance < 60 * 60 else { return nil }
        return best.point
    }
}
