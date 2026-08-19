import SwiftUI
import Charts

struct AreaChartView: View {
    let data: [ChartDataPoint]
    var chartType: ChartBlockConfig.ChartType = .stackedArea
    /// Precomputed by the view model so body doesn't refill series per evaluation.
    var filledData: [ChartDataPoint]? = nil

    private var isMultiSeries: Bool {
        ChartDataPoint.hasMultipleSeries(data)
    }

    private var isHundredPercent: Bool {
        chartType == .hundredPercentStackedArea
    }

    private var displayData: [ChartDataPoint] {
        guard isMultiSeries else { return data }
        return filledData ?? ChartDataPoint.fillMissingSeries(data)
    }

    private var stackingMethod: MarkStackingMethod {
        isHundredPercent ? .normalized : .standard
    }

    var body: some View {
        GeometryReader { geo in
            let stride = ChartDataPoint.xAxisStride(for: data, availableWidth: geo.size.width)
            let series = ChartDataPoint.seriesNames(data)
            let colors = series.indices.map { ChartDataPoint.seriesPalette[$0 % ChartDataPoint.seriesPalette.count] }
            let indexByX = ChartDataPoint.indexByX(data)

            Chart(displayData) { point in
                if isMultiSeries {
                    AreaMark(
                        x: .value("X", point.x),
                        y: .value("Y", point.y),
                        stacking: stackingMethod
                    )
                    .foregroundStyle(by: .value("Series", point.series))
                    .interpolationMethod(.linear)
                } else {
                    AreaMark(
                        x: .value("X", point.x),
                        y: .value("Y", point.y)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.3))
                    .interpolationMethod(.linear)

                    LineMark(
                        x: .value("X", point.x),
                        y: .value("Y", point.y)
                    )
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.linear)
                }
            }
            .chartForegroundStyleScale(domain: series, range: colors)
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
            .chartLegend(isMultiSeries ? .visible : .hidden)
            .transaction { transaction in
                transaction.animation = nil
            }
        }
    }
}
