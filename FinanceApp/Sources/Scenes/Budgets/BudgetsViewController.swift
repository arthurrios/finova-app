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
    
    private var tableHeightConstraint: NSLayoutConstraint?
    private var budgetsData: [DisplayBudgetModel] = []
    
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
        hideKeyboardWhenTappedAround()
        contentView.delegate = self
        setup()
    }
    
    private func setup() {
        navigationController?.setNavigationBarHidden(true, animated: false)
        view.addSubview(contentView)
        buildHierarchy()
        
        loadData()
        setupTable()
    }
    
    private func loadData() {
        budgetsData = viewModel.loadMonthTableViewData()
        
        contentView.updateUI(with: budgetsData, selectedDate: viewModel.selectedDate)
        
        budgetsData.sort { (budget1, budget2) -> Bool in
            return budget1.date > budget2.date
        }
        
        if !budgetsData.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.updateTableHeight()
            }
        }
    }
    
    private func setupTable() {
        contentView.budgetsTableView.register(BudgetsCell.self, forCellReuseIdentifier: BudgetsCell.reuseID)
        contentView.budgetsTableView.dataSource = self
        contentView.budgetsTableView.delegate = self
    }
    
    
    private func updateTableHeight() {
        let rowHeight: CGFloat = 67
        let separatorHeight = CGFloat(max(0, budgetsData.count - 1)) * 1.0
        let contentHeight   = CGFloat(budgetsData.count) * rowHeight + separatorHeight
        
        let maxTableHeight: CGFloat = Metrics.budgetsTableHeight
        let finalHeight = min(contentHeight, maxTableHeight)
        
        if tableHeightConstraint == nil {
            tableHeightConstraint = contentView.budgetsTableView.heightAnchor.constraint(equalToConstant: finalHeight)
            tableHeightConstraint?.isActive = true
        } else {
            tableHeightConstraint?.constant = finalHeight
        }
        
        contentView.budgetsTableView.isScrollEnabled = (contentHeight > maxTableHeight)
        
        view.layoutIfNeeded()
    }
    
    private func buildHierarchy() {
        setupContentViewToBounds(contentView: contentView, respectingSafeArea: false)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateTableHeight()
    }
}

extension BudgetsViewController: BudgetsViewDelegate {
    func didTapAddBudgetButton(monthYearDate: String, budgetAmount: Int) {
        viewModel.addBudget(amount: budgetAmount, monthYearDate: monthYearDate)
    }
    
    func didTapBackButton() {
        flowDelegate?.navBackToDashboard()
    }
}


extension BudgetsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tv: UITableView, numberOfRowsInSection section: Int) -> Int {
        return budgetsData.count
    }
    
    func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let cell = tv.dequeueReusableCell(withIdentifier: BudgetsCell.reuseID, for: ip) as! BudgetsCell
                
        let budgetModel = budgetsData[ip.row]
        cell.configure(date: budgetModel.date, value: budgetModel.amount)
        cell.selectionStyle = .none
        
        return cell
    }
    
    private func parseDateString(_ dateString: String) -> Date {
        
        if let date = DateFormatter.keyToDate.date(from: dateString) {
            return date
        }
        
        return Date()
    }
    
    func tableView(_ tv: UITableView, heightForRowAt ip: IndexPath) -> CGFloat { 52 }
    
    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        return nil
    }
}
