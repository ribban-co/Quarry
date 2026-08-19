import SwiftUI

struct ChartPreviewView: View {
    var viewModel: ChartBlockViewModel

    var body: some View {
        Group {
            if viewModel.isLoadingChart {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading chart data...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let error = viewModel.chartError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.brand)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else if viewModel.chartData.isEmpty {
                ChartEmptyStateView(
                    xAxisColumn: viewModel.config?.xAxisColumn,
                    yAxisColumn: viewModel.config?.yAxisColumn
                )
            } else {
                chartView(for: viewModel.config?.chartType ?? .groupedColumn)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func chartView(for chartType: ChartBlockConfig.ChartType) -> some View {
        switch chartType {
        case .groupedColumn, .stackedColumn, .hundredPercentStackedColumn:
            BarChartView(data: viewModel.chartData, chartType: chartType, normalizedData: viewModel.normalizedChartData)
        case .groupedBar, .stackedBar, .hundredPercentStackedBar:
            HorizontalBarChartView(data: viewModel.chartData, chartType: chartType, normalizedData: viewModel.normalizedChartData)
        case .line:
            LineChartView(data: viewModel.chartData)
        case .stackedArea, .hundredPercentStackedArea:
            AreaChartView(data: viewModel.chartData, chartType: chartType, filledData: viewModel.seriesFilledChartData)
        case .histogram:
            HistogramChartView(data: viewModel.chartData)
        case .scatter:
            ScatterChartView(data: viewModel.chartData)
        case .pie:
            PieChartView(data: viewModel.chartData)
        case .pivotTable:
            PivotTablePlaceholderView()
        }
    }
}

struct ChartEmptyStateView: View {
    let xAxisColumn: String?
    let yAxisColumn: String?

    private let axisInset: CGFloat = 52
    private let gridSpacing: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let originX = axisInset
            let originY = geo.size.height - axisInset
            let endX = geo.size.width - 12
            let endY: CGFloat = 12

            Canvas { context, size in
                drawGrid(context: context, originX: originX, originY: originY, endX: endX, endY: endY)
                drawAxes(context: context, originX: originX, originY: originY, endX: endX, endY: endY)
            }

            yAxisLabel
                .position(x: axisInset / 2, y: geo.size.height / 2)

            xAxisLabel
                .position(x: (originX + endX) / 2, y: originY + (axisInset / 2) + 2)

        }
    }

    // MARK: - Grid

    private func drawGrid(context: GraphicsContext, originX: CGFloat, originY: CGFloat, endX: CGFloat, endY: CGFloat) {
        var gridPath = Path()

        var x = originX + gridSpacing
        while x < endX {
            gridPath.move(to: CGPoint(x: x, y: endY))
            gridPath.addLine(to: CGPoint(x: x, y: originY))
            x += gridSpacing
        }

        var y = originY - gridSpacing
        while y > endY {
            gridPath.move(to: CGPoint(x: originX, y: y))
            gridPath.addLine(to: CGPoint(x: endX, y: y))
            y -= gridSpacing
        }

        context.stroke(gridPath, with: .color(.secondary.opacity(0.08)), lineWidth: 0.5)
    }

    // MARK: - Axes

    private func drawAxes(context: GraphicsContext, originX: CGFloat, originY: CGFloat, endX: CGFloat, endY: CGFloat) {
        let axisColor = Color.secondary.opacity(0.3)
        let dashStyle = StrokeStyle(lineWidth: 1, dash: [6, 4])
        let solidStyle = StrokeStyle(lineWidth: 1)

        var yAxis = Path()
        yAxis.move(to: CGPoint(x: originX, y: originY))
        yAxis.addLine(to: CGPoint(x: originX, y: endY))
        context.stroke(yAxis, with: .color(axisColor), style: dashStyle)

        var yArrow = Path()
        yArrow.move(to: CGPoint(x: originX - 5, y: endY + 8))
        yArrow.addLine(to: CGPoint(x: originX, y: endY))
        yArrow.addLine(to: CGPoint(x: originX + 5, y: endY + 8))
        context.stroke(yArrow, with: .color(axisColor), style: solidStyle)

        var xAxis = Path()
        xAxis.move(to: CGPoint(x: originX, y: originY))
        xAxis.addLine(to: CGPoint(x: endX, y: originY))
        context.stroke(xAxis, with: .color(axisColor), style: dashStyle)

        var xArrow = Path()
        xArrow.move(to: CGPoint(x: endX - 8, y: originY - 5))
        xArrow.addLine(to: CGPoint(x: endX, y: originY))
        xArrow.addLine(to: CGPoint(x: endX - 8, y: originY + 5))
        context.stroke(xArrow, with: .color(axisColor), style: solidStyle)
    }

    // MARK: - Labels

    @ViewBuilder
    private var yAxisLabel: some View {
        if let col = yAxisColumn {
            axisTag(col)
                .rotationEffect(.degrees(-90))
        } else {
            Text("No Y-axis")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.quaternary)
                )
                .rotationEffect(.degrees(-90))
        }
    }

    @ViewBuilder
    private var xAxisLabel: some View {
        HStack(spacing: 6) {
            if let col = xAxisColumn {
                Text("X-axis")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                axisTag(col)
            } else {
                Text("No X-axis")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(.quaternary)
                    )
            }
        }
    }

    private func axisTag(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quinary)
            .clipShape(.rect(cornerRadius: 4))
    }

}
