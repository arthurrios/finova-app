//
//  AllocationHistoryPreviewView.swift
//  Finova
//
//  Created by Arthur Rios on 17/10/26.
//

import SwiftUI
import UIKit

/// The history section on the allocation details screen: six months of this category in miniature,
/// one line saying how often it stayed on plan, and the way into the full history.
///
/// It sits where the question comes up. Someone looking at one month of a category is the person most
/// likely to ask "is this month unusual?", so the answer is on that screen rather than behind a menu.
final class AllocationHistoryPreviewView: UIView {

    var onTap: (() -> Void)?

    private let headerView = CardHeader(headerTitle: "budgetHistory.preview.header".localized)

    private let contentView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.layer.borderWidth = 1
        view.layer.borderColor = Colors.gray300.cgColor
        view.layer.cornerRadius = CornerRadius.extraLarge
        view.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var hostingController: UIHostingController<AllocationHistoryPreview>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        headerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerView)
        addSubview(contentView)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),

            contentView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(series: BudgetHistorySeries, selectedAnchor: Int, isValuesHidden: Bool) {
        let rootView = AllocationHistoryPreview(
            series: series, selectedAnchor: selectedAnchor, isValuesHidden: isValuesHidden
        ) { [weak self] in
            self?.onTap?()
        }

        // Swap the root view rather than the controller, so the chart animates between states.
        if let hostingController {
            hostingController.rootView = rootView
            return
        }

        let hosting = UIHostingController(rootView: rootView)
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.sizingOptions = .intrinsicContentSize
        contentView.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: contentView.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        hostingController = hosting
    }
}

/// The SwiftUI body of the preview. The whole card is one button.
struct AllocationHistoryPreview: View {
    let series: BudgetHistorySeries
    let selectedAnchor: Int
    let isValuesHidden: Bool
    let onTap: () -> Void

    private var summary: String {
        let scored = series.scoredMonths.count
        guard scored > 0 else { return "budgetHistory.preview.notEnough".localized }
        return String(
            format: "budgetHistory.preview.summary.format".localized, series.monthsOnPlan, scored)
    }

    var body: some View {
        SwiftUI.Button(action: onTap) {
            VStack(alignment: .leading, spacing: Metrics.spacing3) {
                BudgetHistoryChartView(
                    months: series.months,
                    selectedAnchor: selectedAnchor,
                    isValuesHidden: isValuesHidden,
                    isCompact: true
                )
                .frame(height: 76)
                // The chart's own selection gesture is off in compact mode; this keeps the whole card
                // a single tap target.
                .allowsHitTesting(false)

                HStack(spacing: Metrics.spacing2) {
                    Text(summary)
                        .font(Font(Fonts.textXS.font))
                        .foregroundStyle(Color(Colors.gray500))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Metrics.spacing2)
                    HStack(spacing: 2) {
                        Text("budgetHistory.preview.cta".localized)
                            .font(Font(Fonts.textSMBold.font))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(Color(Colors.mainMagenta))
                    .fixedSize()
                }
            }
            .padding(Metrics.spacing5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("budgetHistory.preview.cta".localized)
        .accessibilityValue(summary)
        .accessibilityAddTraits(.isButton)
    }
}
