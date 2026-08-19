import AppKit
import SwiftUI

final class DashboardChartItem: DashboardBaseItem {

    static let identifier = NSUserInterfaceItemIdentifier("DashboardChartItem")

    override var minimumContentHeight: CGFloat { 280 }

    private var hostingView: NSHostingView<AnyView>?

    func configure(block: NotebookBlock, viewModel: ChartBlockViewModel, isPublished: Bool = false) {
        configureBase(block: block, isPublished: isPublished)

        let chartView = ChartPreviewView(viewModel: viewModel)
        if let existing = hostingView {
            existing.rootView = AnyView(chartView)
        } else {
            let hosting = NSHostingView(rootView: AnyView(chartView))
            hosting.translatesAutoresizingMaskIntoConstraints = false
            blockContainer.addSubview(hosting)
            hostingView = hosting

            NSLayoutConstraint.activate([
                hosting.topAnchor.constraint(equalTo: blockContainer.topAnchor),
                hosting.leadingAnchor.constraint(equalTo: blockContainer.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: blockContainer.trailingAnchor),
                hosting.bottomAnchor.constraint(equalTo: blockContainer.bottomAnchor),
            ])
        }
    }
}
