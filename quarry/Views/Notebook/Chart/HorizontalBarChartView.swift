import SwiftUI
import Charts

struct HorizontalBarChartView: View {
    let data: [ChartDataPoint]
    var chartType: ChartBlockConfig.ChartType = .groupedBar
    /// Precomputed by the view model so body doesn't renormalize per evaluation.
    var normalizedData: [ChartDataPoint]? = nil

    private var isMultiSeries: Bool {
        ChartDataPoint.hasMultipleSeries(data)
    }

    private var isHundredPercent: Bool {
        chartType == .hundredPercentStackedBar
    }

    private var displayData: [ChartDataPoint] {
        if isHundredPercent, isMultiSeries {
            return normalizedData ?? ChartDataPoint.normalized(data)
        }
        return data
    }

    private var categories: [String] {
        var ordered: [String] = []
        var seen: Set<String> = []
        for point in data {
            if seen.insert(point.x).inserted {
                ordered.append(point.x)
            }
        }
        return ordered
    }

    private var barThickness: CGFloat {
        let seriesCount = isMultiSeries && chartType == .groupedBar
            ? max(1, ChartDataPoint.seriesNames(data).count)
            : 1
        return seriesCount > 2 ? 8 : 20
    }

    private var labelAreaWidth: CGFloat {
        let maxChars = min(categories.map(\.count).max() ?? 8, 16)
        return CGFloat(maxChars) * 7 + 12
    }

    var body: some View {
        GeometryReader { _ in
            let series = ChartDataPoint.seriesNames(data)
            let colors = series.indices.map { ChartDataPoint.seriesPalette[$0 % ChartDataPoint.seriesPalette.count] }

            HStack(spacing: 8) {
                chartLabels
                    .frame(width: labelAreaWidth)

                Chart(displayData) { point in
                    if isMultiSeries {
                        if chartType == .groupedBar {
                            BarMark(
                                x: .value("Y", point.y),
                                y: .value("X", point.x),
                                height: .fixed(barThickness)
                            )
                            .foregroundStyle(by: .value("Series", point.series))
                            .position(by: .value("Series", point.series))
                            .clipShape(.rect(cornerRadius: 3))
                        } else {
                            BarMark(
                                x: .value("Y", point.y),
                                y: .value("X", point.x),
                                height: .fixed(barThickness)
                            )
                            .foregroundStyle(by: .value("Series", point.series))
                        }
                    } else {
                        BarMark(
                            x: .value("Y", point.y),
                            y: .value("X", point.x),
                            height: .fixed(barThickness)
                        )
                        .foregroundStyle(Color.accentColor)
                        .clipShape(.rect(cornerRadius: 3))
                    }
                }
                .chartForegroundStyleScale(domain: series, range: colors)
                .hundredPercentXScale(isActive: isHundredPercent)
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                if isHundredPercent {
                                    Text(number.formatted(.percent))
                                        .font(.caption)
                                } else {
                                    Text(number.formatted(.number.notation(.compactName)))
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
                .chartYAxis(.hidden)
                .chartLegend(isMultiSeries ? .visible : .hidden)
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
        }
    }

    private var chartLabels: some View {
        VStack(spacing: 0) {
            ForEach(categories, id: \.self) { category in
                Text(category.count > 16 ? String(category.prefix(14)) + "…" : category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }
        }
        .padding(.bottom, 20)
    }
}

private extension View {
    @ViewBuilder
    func hundredPercentXScale(isActive: Bool) -> some View {
        if isActive {
            chartXScale(domain: 0...1 as ClosedRange<Double>)
        } else {
            self
        }
    }
}
