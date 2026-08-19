import SwiftUI
import Charts

struct HistogramChartView: View {
    let data: [ChartDataPoint]

    var body: some View {
        GeometryReader { geo in
            let stride = ChartDataPoint.xAxisStride(for: data, availableWidth: geo.size.width)
            let indexByX = ChartDataPoint.indexByX(data)
            Chart(data) { point in
                BarMark(
                    x: .value("X", point.x),
                    y: .value("Y", point.y)
                )
                .foregroundStyle(Color.accentColor.opacity(0.8))
            }
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
