//
//  ImportHistoryViewController.swift
//  Finova
//
//  The entry point for the whole feature: pick a file, or undo a past import.
//

import UIKit

final class ImportHistoryViewController: UIViewController {

    private let contentView: ImportHistoryView
    private let viewModel: ImportHistoryViewModel
    weak var flowDelegate: ImportFlowDelegate?

    private let documentImporter = CSVDocumentImporter()

    init(
        contentView: ImportHistoryView,
        viewModel: ImportHistoryViewModel,
        flowDelegate: ImportFlowDelegate?
    ) {
        self.contentView = contentView
        self.viewModel = viewModel
        self.flowDelegate = flowDelegate
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() { view = contentView }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "import.history.title".localized

        contentView.delegate = self
        contentView.tableView.dataSource = self
        contentView.tableView.delegate = self
        contentView.tableView.register(
            ImportHistoryCell.self, forCellReuseIdentifier: ImportHistoryCell.identifier)

        bindViewModel()

        NotificationCenter.default.addObserver(
            self, selector: #selector(refresh), name: .importBatchesDidChange, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.refresh()
    }

    @objc private func refresh() { viewModel.refresh() }

    private func bindViewModel() {
        viewModel.onBatchesUpdated = { [weak self] in
            guard let self else { return }
            self.contentView.tableView.reloadData()
            self.contentView.updateEmptyState(isEmpty: self.viewModel.isEmpty)
        }

        viewModel.onParsing = { [weak self] parsing in
            self?.contentView.setParsing(parsing)
        }

        viewModel.onParsed = { [weak self] file, plan in
            guard let self else { return }
            // A file we could not read confidently gets the mapping screen first; anything else goes
            // straight to the diff, which is the only step that is never skipped. An unusable schema
            // (no date or no amount column identified) lands here too rather than in an error alert —
            // the user can point at the right columns themselves.
            if plan.confidence.band == .low || !plan.schema.isUsable {
                self.flowDelegate?.navigateToImportMapping(file: file, plan: plan)
            } else {
                self.flowDelegate?.navigateToImportReview(file: file, plan: plan)
            }
        }

        viewModel.onError = { [weak self] message in
            self?.showErrorAlert(message: message)
        }
    }

    private func showErrorAlert(message: String) {
        let alert = UIAlertController(
            title: "import.error.title".localized, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "alert.ok".localized, style: .default))
        present(alert, animated: true)
    }
}

// MARK: - ImportHistoryViewDelegate

extension ImportHistoryViewController: ImportHistoryViewDelegate {

    func didTapImportFile() {
        documentImporter.present(from: self) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let file):
                self.viewModel.parse(file: file)
            case .failure(.cancelled):
                break   // the user backed out of the picker; not an error
            case .failure(let error):
                self.showErrorAlert(message: error.userMessage)
            }
        }
    }
}

// MARK: - Table view

extension ImportHistoryViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.batches.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: ImportHistoryCell.identifier, for: indexPath) as? ImportHistoryCell else {
            return UITableViewCell()
        }
        let batch = viewModel.batches[indexPath.row]
        cell.configure(
            batch: batch,
            summary: viewModel.summary(for: batch),
            range: viewModel.dateRange(for: batch))
        return cell
    }

    func tableView(
        _ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let batch = viewModel.batches[indexPath.row]
        guard batch.status.isRollbackable else { return nil }

        let undo = UIContextualAction(
            style: .destructive, title: "import.history.undo".localized
        ) { [weak self] _, _, done in
            self?.confirmUndo(of: batch)
            done(true)
        }
        undo.backgroundColor = Colors.mainRed
        return UISwipeActionsConfiguration(actions: [undo])
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let batch = viewModel.batches[indexPath.row]

        let live = viewModel.liveRowCount(for: batch)
        let details = [
            String(format: "import.history.detail.rows".localized, batch.rowsInserted, live),
            String(format: "import.history.detail.skipped".localized, batch.rowsSkipped, batch.rowsFailed),
            batch.notes,
        ].compactMap { $0 }.joined(separator: "\n\n")

        let alert = UIAlertController(
            title: batch.sourceFilename, message: details, preferredStyle: .actionSheet)
        if batch.status.isRollbackable {
            alert.addAction(UIAlertAction(
                title: "import.history.undo".localized, style: .destructive) { [weak self] _ in
                    self?.confirmUndo(of: batch)
                })
        }
        alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = tableView
            popover.sourceRect = tableView.rectForRow(at: indexPath)
        }
        present(alert, animated: true)
    }

    private func confirmUndo(of batch: ImportBatch) {
        let live = viewModel.liveRowCount(for: batch)
        showConfirmation(
            title: "import.history.undo.confirm.title".localized,
            message: String(format: "import.history.undo.confirm.message".localized,
                            live, batch.sourceFilename),
            okTitle: "import.history.undo".localized,
            onOk: { [weak self] in self?.viewModel.rollback(batch) })
    }
}
