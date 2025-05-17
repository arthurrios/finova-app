//
//  BudgetsViewController.swift
//  FinanceApp
//
//  Created by Arthur Rios on 16/05/25.
//

import Foundation
import UIKit

final class BudgetsViewController: UIViewController {
    let contentView: BudgetsView
    let viewModel: BudgetsViewModel
    public weak var flowDelegate: BudgetsFlowDelegate?
    
    init(contentView: BudgetsView, viewModel: BudgetsViewModel, flowDelegate: BudgetsFlowDelegate? = nil) {
        self.contentView = contentView
        self.viewModel = viewModel
        self.flowDelegate = flowDelegate
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        contentView.delegate = self
        setup()
    }
    
    private func setup() {
        navigationController?.setNavigationBarHidden(true, animated: false)
        view.addSubview(contentView)
        buildHierarchy()
    }
    
    private func buildHierarchy() {
        setupContentViewToBounds(contentView: contentView, respectingSafeArea: false)
    }
}

extension BudgetsViewController: BudgetsViewDelegate {
    func didTapAddBudgetButton() {
        //
    }
}
