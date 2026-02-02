//
//  BudgetAllocationDetailsViewController.swift
//  Finova
//
//  Created by Arthur Rios on 02/02/26.
//

import UIKit

final class BudgetAllocationDetailsViewController: UIViewController {
    
    // MARK: - Properties
    private let mainView = BudgetAllocationDetailsView()
    private let allocation: BudgetAllocation
    weak var flowDelegate: BudgetAllocationDetailsFlowDelegate?
    
    init(allocation: BudgetAllocation) {
        self.allocation = allocation
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        view = mainView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.setNavigationBarHidden(true, animated: false)
        setupActions()
        mainView.configure(with: allocation)
    }
    
    private func setupActions() {
        mainView.backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
    }
    
    @objc
    private func backTapped() {
        flowDelegate?.dismissAllocationDetails()
    }
}
