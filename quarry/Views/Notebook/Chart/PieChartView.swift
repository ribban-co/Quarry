import SwiftUI
import Charts

struct PieChartView: View {
    let data: [ChartDataPoint]

    private var positiveData: [ChartDataPoint] {
        data.filter { $0.y > 0 }
    }

    var body: some View {
        let categories = positiveData.map(\.x)
        let colors = categories.indices.map { ChartDataPoint.seriesPalette[$0 % ChartDataPoint.seriesPalette.count] }

        Chart(positiveData) { point in
            SectorMark(
                angle: .value("Value", point.y),
                innerRadius: .ratio(0.4),
                angularInset: 1.5
            )
            .cornerRadius(3)
            .foregroundStyle(by: .value("Category", point.x))
        }
        .chartForegroundStyleScale(domain: categories, range: colors)
        .chartLegend(position: .bottom, spacing: 8)
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}
