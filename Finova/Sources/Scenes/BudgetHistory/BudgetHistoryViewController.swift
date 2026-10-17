//
//  BudgetHistoryViewController.swift
//  Finova
//
//  Created by Arthur Rios on 17/10/26.
//

import SwiftUI
import UIKit

protocol BudgetHistoryFlowDelegate: AnyObject {
    func dismissBudgetHistory()
    func navigateToTransactionDetails(transaction: Transaction)
}

/// Past months of the budget and of each allocation, against their plans.
///
/// The header is UIKit, so it is the same header - glass back button, title, eye - as the allocation
/// details screen this opens from. Everything under it is SwiftUI, because the chart is.
final class BudgetHistoryViewController: UIViewController {

    weak var flowDelegate: BudgetHistoryFlowDelegate?
    private let viewModel: BudgetHistoryViewModel
    private let subtitle: String
    private lazy var hostingController = UIHostingController(
        rootView: BudgetHistoryContentView(viewModel: viewModel))

    init(viewModel: BudgetHistoryViewModel, subtitle: String) {
        self.viewModel = viewModel
        self.subtitle = subtitle
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Header

    private let headerContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let headerItemsView: UIView = {
        let view = UIView()
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Metrics.spacing4, leading: Metrics.spacing5, bottom: Metrics.spacing5,
            trailing: Metrics.spacing5)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let headerBorderView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray300
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var backButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: "chevronLeft")?.withRenderingMode(.alwaysTemplate), for: .normal)
        button.imageView?.contentMode = .scaleAspectFit
        button.accessibilityLabel = "budgetHistory.a11y.back".localized
        button.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 26.0, *) {
            button.tintColor = Colors.gray700
        } else {
            button.tintColor = Colors.gray500
        }
        button.addTarget(self, action: #selector(didTapBack), for: .touchUpInside)
        return button
    }()

    private let backButtonGlassContainer: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        return container
    }()

    private let hideValuesButton = HideValuesButton(style: .onHeader)

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleSM
        label.textColor = Colors.gray700
        label.text = "budgetHistory.title".localized
        label.applyStyle()
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray500
        return label
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.setNavigationBarHidden(true, animated: false)
        view.backgroundColor = Colors.gray200
        subtitleLabel.text = subtitle
        setupHeader()
        embedContent()
        viewModel.onOpenTransaction = { [weak self] transaction in
            self?.flowDelegate?.navigateToTransactionDetails(transaction: transaction)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.load()
    }

    private func setupHeader() {
        let textStack = UIStackView(
            axis: .vertical, spacing: Metrics.spacing1, arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(headerContainerView)
        headerContainerView.addSubview(headerItemsView)
        headerContainerView.addSubview(headerBorderView)
        headerItemsView.addSubview(backButtonGlassContainer)
        backButtonGlassContainer.addSubview(backButton)
        backButtonGlassContainer.applyClearGlass(cornerRadius: 18)
        backButtonGlassContainer.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(didTapBack)))
        headerItemsView.addSubview(textStack)
        headerItemsView.addSubview(hideValuesButton)

        NSLayoutConstraint.activate([
            headerContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerContainerView.heightAnchor.constraint(equalToConstant: Metrics.headerHeight),

            headerItemsView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerItemsView.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor),
            headerItemsView.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor),
            headerItemsView.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor),

            headerBorderView.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor),
            headerBorderView.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor),
            headerBorderView.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor),
            headerBorderView.heightAnchor.constraint(equalToConstant: 1),

            backButtonGlassContainer.topAnchor.constraint(
                equalTo: headerItemsView.layoutMarginsGuide.topAnchor),
            backButtonGlassContainer.leadingAnchor.constraint(
                equalTo: headerItemsView.layoutMarginsGuide.leadingAnchor),
            backButtonGlassContainer.widthAnchor.constraint(equalToConstant: 36),
            backButtonGlassContainer.heightAnchor.constraint(equalToConstant: 36),

            backButton.topAnchor.constraint(equalTo: backButtonGlassContainer.topAnchor),
            backButton.leadingAnchor.constraint(equalTo: backButtonGlassContainer.leadingAnchor),
            backButton.trailingAnchor.constraint(equalTo: backButtonGlassContainer.trailingAnchor),
            backButton.bottomAnchor.constraint(equalTo: backButtonGlassContainer.bottomAnchor),

            hideValuesButton.trailingAnchor.constraint(
                equalTo: headerItemsView.layoutMarginsGuide.trailingAnchor),
            hideValuesButton.centerYAnchor.constraint(equalTo: backButtonGlassContainer.centerYAnchor),

            textStack.leadingAnchor.constraint(
                equalTo: backButtonGlassContainer.trailingAnchor, constant: Metrics.spacing4),
            textStack.centerYAnchor.constraint(equalTo: backButtonGlassContainer.centerYAnchor),
            textStack.trailingAnchor.constraint(
                lessThanOrEqualTo: hideValuesButton.leadingAnchor, constant: -Metrics.spacing3),
        ])
    }

    private func embedContent() {
        addChild(hostingController)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(hostingController.view, belowSubview: headerContainerView)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hostingController.didMove(toParent: self)
    }

    @objc private func didTapBack() {
        flowDelegate?.dismissBudgetHistory()
    }
}
