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
    
    init(
        contentView: BudgetsView, viewModel: BudgetsViewModel, flowDelegate: BudgetsFlowDelegate? = nil
    ) {
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
        contentView.suggestedAmount = { [weak self] in self?.viewModel.suggestedBudget(monthYearDate: $0) ?? 0 }
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
        viewModel.followIncome.recomputeIfEnabled()
        let follow = viewModel.followIncome.settings
        contentView.setFollowIncome(enabled: follow.isEnabled, percent: follow.percent)
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
        contentView.budgetsTableView.register(
            BudgetsCell.self, forCellReuseIdentifier: BudgetsCell.reuseID)
        contentView.budgetsTableView.dataSource = self
        contentView.budgetsTableView.delegate = self
    }
    
    private func updateTableHeight() {
        let rowHeight: CGFloat = 52
        let separatorHeight = CGFloat(max(0, budgetsData.count - 1)) * 1.0
        let contentHeight = CGFloat(budgetsData.count) * rowHeight + separatorHeight
        
        let maxTableHeight: CGFloat = Metrics.budgetsTableHeight
        let finalHeight = min(contentHeight, maxTableHeight)
        
        if tableHeightConstraint == nil {
            tableHeightConstraint = contentView.budgetsTableView.heightAnchor.constraint(
                equalToConstant: finalHeight)
            // The list gives way when the form grows (repeat row, "follows income" rows), so the
            // form is never squashed.
            tableHeightConstraint?.priority = .defaultHigh
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
    
    private func showErrorAlert(error: Error) {
        let message: String
        switch error {
        case BudgetsViewModel.BudgetError.invalidDateFormat:
            message = "budgets.error.invalidDate".localized
        case DBError.openDatabaseFailed:
            message = "budgets.error.dbOpenFailed".localized
        case DBError.prepareFailed(let msg):
            message = msg.isEmpty ? "budgets.error.dbPrepareFailed".localized : msg
        default:
            message = error.localizedDescription
        }
        
        let alertController = UIAlertController(
            title: "alert.error.title".localized,
            message: message,
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: "alert.ok".localized, style: .default))
        
        DispatchQueue.main.async {
            self.present(alertController, animated: true)
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateTableHeight()
    }
}

extension BudgetsViewController: BudgetsViewDelegate {
    func didTapAddBudgetButton(monthYearDate: String, budgetAmount: Int) {
        let result = viewModel.addBudget(
            amount: budgetAmount,
            monthYearDate: monthYearDate
        )
        
        switch result {
        case .success:
            viewModel.keepFixed(months: BudgetsViewModel.monthAnchor(of: monthYearDate).map { [$0] } ?? [])
            loadData()
            contentView.budgetsTableView.reloadData()
            contentView.clearTextFields()
            CoachMarkCenter.shared.post(.budgetSaved)
        case .failure(let error):
            
            switch error {
            case BudgetsViewModel.BudgetError.budgetAlreadyExists:
                let alertController = UIAlertController(
                    title: "budgets.alert.budgetAlreadyExists.title".localized,
                    message: "budgets.alert.budgetAlreadyExists.description".localized, preferredStyle: .alert
                )
                
                let overwriteAction = UIAlertAction(
                    title: "alert.update.confirm".localized, style: .default
                ) { _ in
                    let updateResult = self.viewModel.forceUpdateBudget(
                        amount: budgetAmount, monthYearDate: monthYearDate)
                    
                    switch updateResult {
                    case .success:
                        self.viewModel.keepFixed(
                            months: BudgetsViewModel.monthAnchor(of: monthYearDate).map { [$0] } ?? [])
                        self.loadData()
                        self.contentView.budgetsTableView.reloadData()
                        self.contentView.clearTextFields()
                        CoachMarkCenter.shared.post(.budgetSaved)
                    case .failure(let updateError):
                        self.showErrorAlert(error: updateError)
                    }
                }
                
                let cancelAction = UIAlertAction(title: "alert.cancel".localized, style: .cancel)
                
                alertController.addAction(overwriteAction)
                alertController.addAction(cancelAction)
                
                DispatchQueue.main.async {
                    self.present(alertController, animated: true)
                }
                return
            default:
                break
            }
        }
    }
    
    func didTapAddBudgets(monthYearDate: String, budgetAmount: Int, endMonth: Int) {
        let conflicts = viewModel.existingBudgetMonths(monthYearDate: monthYearDate, endMonth: endMonth)
        guard !conflicts.isEmpty else {
            saveBudgets(amount: budgetAmount, monthYearDate: monthYearDate, endMonth: endMonth, replaceExisting: true)
            return
        }

        // Same shape as the allocation conflict alert: the first three months, then "+N".
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let names = conflicts.map { formatter.string(from: Date(timeIntervalSince1970: TimeInterval($0))) }
        let monthsList = names.prefix(3).joined(separator: ", ")
        let additionalCount = names.count > 3 ? " (+\(names.count - 3))" : ""

        let alert = UIAlertController(
            title: "budgets.multi.conflict.title".localized,
            message: String(format: "budgets.multi.conflict.message".localized, monthsList + additionalCount),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: "budgets.multi.conflict.replace".localized, style: .destructive
        ) { [weak self] _ in
            self?.saveBudgets(
                amount: budgetAmount, monthYearDate: monthYearDate, endMonth: endMonth, replaceExisting: true)
        })
        alert.addAction(UIAlertAction(
            title: "budgets.multi.conflict.keep".localized, style: .default
        ) { [weak self] _ in
            self?.saveBudgets(
                amount: budgetAmount, monthYearDate: monthYearDate, endMonth: endMonth, replaceExisting: false)
        })
        alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel))
        present(alert, animated: true)
    }

    private func saveBudgets(amount: Int, monthYearDate: String, endMonth: Int, replaceExisting: Bool) {
        switch viewModel.addBudgets(
            amount: amount, monthYearDate: monthYearDate, endMonth: endMonth, replaceExisting: replaceExisting)
        {
        case .success(let written):
            viewModel.keepFixed(months: written)
            loadData()
            contentView.budgetsTableView.reloadData()
            contentView.clearTextFields()
            // Budgets feed the negative-balance warnings, so re-check them now for every month.
            BalanceMonitorManager.shared.forceTriggerBalanceMonitoring()
            CoachMarkCenter.shared.post(.budgetSaved)
        case .failure(let error):
            showErrorAlert(error: error)
        }
    }

    // MARK: Budget follows income

    func didToggleFollowIncome(isOn: Bool) {
        guard isOn else {
            viewModel.followIncome.disable()
            loadData()
            contentView.budgetsTableView.reloadData()
            return
        }
        let percent = viewModel.followIncome.settings.percent
        let alert = UIAlertController(
            title: "budgets.followIncome.enable.title".localized,
            message: String(format: "budgets.followIncome.enable.message".localized, percent),
            preferredStyle: .alert)
        let apply: (Bool) -> Void = { [weak self] includePast in
            guard let self else { return }
            self.viewModel.followIncome.enable(percent: percent, includePastMonths: includePast)
            self.loadData()
            self.contentView.budgetsTableView.reloadData()
        }
        alert.addAction(UIAlertAction(title: "budgets.followIncome.enable.fromNow".localized, style: .default) { _ in
            apply(false)
        })
        alert.addAction(UIAlertAction(title: "budgets.followIncome.enable.includePast".localized, style: .default) { _ in
            apply(true)
        })
        alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel) { [weak self] _ in
            self?.contentView.followIncomeSwitch.setOn(false, animated: true)
        })
        present(alert, animated: true)
    }

    func didPickFollowIncomePercent(_ percent: Int) {
        viewModel.followIncome.setPercent(percent)
        loadData()
        contentView.budgetsTableView.reloadData()
    }

    func didTapCustomFollowIncomePercent() {
        let range = BudgetFollowsIncomeService.percentRange
        let alert = UIAlertController(
            title: "budgets.followIncome.percent".localized,
            message: String(format: "budgets.followIncome.percent.range".localized, range.lowerBound, range.upperBound),
            preferredStyle: .alert)
        alert.addTextField { field in
            field.keyboardType = .numberPad
            field.text = "\(self.viewModel.followIncome.settings.percent)"
        }
        alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel))
        alert.addAction(UIAlertAction(title: "alert.ok".localized, style: .default) { [weak self, weak alert] _ in
            guard let text = alert?.textFields?.first?.text, let value = Int(text), range.contains(value) else { return }
            self?.didPickFollowIncomePercent(value)
        })
        present(alert, animated: true)
    }

    func didTapBackButton() {
        flowDelegate?.navBackToDashboard()
    }

    func didTapManageTags() {
        flowDelegate?.navigateToAllocationTags()
    }
}

extension BudgetsViewController: UITableViewDataSource, UITableViewDelegate, BudgetsCellDelegate {
    func budgetCellDidRequestDelete(_ cell: BudgetsCell, completion: @escaping (Bool) -> Void) {
        guard let ip = contentView.budgetsTableView.indexPath(for: cell) else { return }
        let model = budgetsData[ip.row]
        
        let monthDate = DateFormatter.monthYearFormatter.string(from: model.date)
        let anchor = model.date.monthAnchor
        let follow = viewModel.followIncome
        let settings = follow.settings

        // A fixed month inside the "follows income" range can rejoin instead of being deleted.
        if settings.isEnabled, anchor >= settings.startMonth, settings.optedOutMonths.contains(anchor) {
            let alert = UIAlertController(
                title: "budget.delete.title".localized,
                message: "budgets.followIncome.fixedMonth.message".localized,
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "budgets.followIncome.fixedMonth.rejoin".localized, style: .default) {
                [weak self] _ in
                follow.optIn(month: anchor)
                self?.loadData()
                self?.contentView.budgetsTableView.reloadData()
                completion(false)
            })
            alert.addAction(UIAlertAction(title: "alert.delete".localized, style: .destructive) { [weak self] _ in
                self?.performDelete(monthDate: monthDate, at: ip, completion: completion)
            })
            alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel) { _ in completion(false) })
            present(alert, animated: true)
            return
        }

        showConfirmation(
            title: "budget.delete.title".localized, message: "delete.confirmation".localized,
            okTitle: "alert.delete".localized
        ) {
            // Deleting a month that follows income keeps it empty: without the opt-out the next
            // recompute would write it straight back.
            if follow.follows(month: anchor) { follow.optOut(month: anchor) }
            self.performDelete(monthDate: monthDate, at: ip, completion: completion)
        } onCancel: {
            completion(false)
        }
    }

    private func performDelete(monthDate: String, at ip: IndexPath, completion: @escaping (Bool) -> Void) {
        switch viewModel.deleteBudget(monthYearDate: monthDate) {
        case .success:
            budgetsData.remove(at: ip.row)
            contentView.budgetsTableView.deleteRows(at: [ip], with: .automatic)
            updateTableHeight()
            contentView.toggleEmptyState(budgetsData.isEmpty)
            completion(true)
        case .failure(let error):
            showErrorAlert(error: error)
            completion(false)
        }
    }
    
    func tableView(_ tv: UITableView, numberOfRowsInSection section: Int) -> Int {
        return budgetsData.count
    }
    
    func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let cell = tv.dequeueReusableCell(withIdentifier: BudgetsCell.reuseID, for: ip) as! BudgetsCell
        
        cell.delegate = self
        
        let budgetModel = budgetsData[ip.row]
        cell.configure(
            date: budgetModel.date, value: budgetModel.amount,
            note: viewModel.note(forMonth: budgetModel.date.monthAnchor, amount: budgetModel.amount))
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
}
