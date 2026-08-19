import SwiftUI
import Charts

struct LineChartView: View {
    let data: [ChartDataPoint]

    private var isMultiSeries: Bool {
        ChartDataPoint.hasMultipleSeries(data)
    }

    var body: some View {
        GeometryReader { geo in
            let stride = ChartDataPoint.xAxisStride(for: data, availableWidth: geo.size.width)
            let series = ChartDataPoint.seriesNames(data)
            let colors = series.indices.map { ChartDataPoint.seriesPalette[$0 % ChartDataPoint.seriesPalette.count] }
            let indexByX = ChartDataPoint.indexByX(data)

            Chart(data) { point in
                if isMultiSeries {
                    LineMark(
                        x: .value("X", point.x),
                        y: .value("Y", point.y)
                    )
                    .foregroundStyle(by: .value("Series", point.series))
                    .interpolationMethod(.linear)

                    PointMark(
                        x: .value("X", point.x),
                        y: .value("Y", point.y)
                    )
                    .foregroundStyle(by: .value("Series", point.series))
                    .symbolSize(20)
                } else {
                    LineMark(
                        x: .value("X", point.x),
                        y: .value("Y", point.y)
                    )
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.linear)

                    PointMark(
                        x: .value("X", point.x),
                        y: .value("Y", point.y)
                    )
                    .foregroundStyle(Color.accentColor)
                    .symbolSize(20)
                }
            }
            .chartForegroundStyleScale(domain: series, range: colors)
            .chartLegend(isMultiSeries ? .visible : .hidden)
            .chartXAxis {
                AxisMarks(values: .automatic) { value in
                    if let label = value.as(String.self),
                       let index = indexByX[label],
                       index % stride == 0 {
                        AxisValueLabel {
                            Text(data[index].truncatedX)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(number.formatted(.number.notation(.compactName)))
                                .font(.caption)
                        }
                    }
                }
            }
            .transaction { transaction in
                transaction.animation = nil
            }
        }
    }
}
