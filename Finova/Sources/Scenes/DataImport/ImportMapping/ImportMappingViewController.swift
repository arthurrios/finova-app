//
//  ImportMappingViewController.swift
//  Finova
//
//  A confirmation screen, not a form: every field arrives pre-filled with the engine's best guess,
//  and the ones it was least sure about are marked.
//

import UIKit

final class ImportMappingView: UIView {

    weak var delegate: ImportMappingViewDelegate?

    let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.backgroundColor = .clear
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    private let confirmButton = Button(variant: .base, label: "import.mapping.confirm".localized)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Colors.gray200
        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tableView)
        addSubview(confirmButton)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(
                equalTo: confirmButton.topAnchor, constant: -Metrics.spacing3),

            confirmButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing4),
            confirmButton.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -Metrics.spacing4),
            confirmButton.heightAnchor.constraint(equalToConstant: Metrics.buttonHeight),
            confirmButton.bottomAnchor.constraint(
                equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -Metrics.spacing4),
        ])

        confirmButton.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func confirmTapped() { delegate?.didTapConfirmMapping() }

    func setLoading(_ loading: Bool) {
        if loading { confirmButton.startLoading() } else { confirmButton.stopLoading() }
    }
}

protocol ImportMappingViewDelegate: AnyObject {
    func didTapConfirmMapping()
}

final class ImportMappingViewController: UIViewController {

    private let contentView: ImportMappingView
    private let viewModel: ImportMappingViewModel
    weak var flowDelegate: ImportFlowDelegate?

    private let fields = ImportMappingViewModel.Field.allCases

    init(
        contentView: ImportMappingView,
        viewModel: ImportMappingViewModel,
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
        title = "import.mapping.title".localized

        contentView.delegate = self
        contentView.tableView.dataSource = self
        contentView.tableView.delegate = self
        contentView.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "MappingCell")

        viewModel.onSchemaUpdated = { [weak self] in self?.contentView.tableView.reloadData() }
        viewModel.onError = { [weak self] message in
            self?.contentView.setLoading(false)
            let alert = UIAlertController(
                title: "import.error.title".localized, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "alert.ok".localized, style: .default))
            self?.present(alert, animated: true)
        }
        viewModel.onReplanned = { [weak self] plan in
            guard let self else { return }
            self.contentView.setLoading(false)
            self.flowDelegate?.didConfirmImportMapping(file: self.viewModel.file, plan: plan)
        }
    }
}

extension ImportMappingViewController: ImportMappingViewDelegate {
    func didTapConfirmMapping() {
        contentView.setLoading(true)
        viewModel.confirm()
    }
}

extension ImportMappingViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        fields.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "import.mapping.header".localized
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "import.mapping.footer".localized
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "MappingCell", for: indexPath)
        let field = fields[indexPath.row]

        var configuration = UIListContentConfiguration.valueCell()
        configuration.text = field.title
        configuration.secondaryText = viewModel.value(for: field)
        configuration.textProperties.font = Fonts.textSM.font
        configuration.secondaryTextProperties.font = Fonts.textSM.font
        // The fields inference was least sure about are the ones worth a second look.
        configuration.textProperties.color = viewModel.weakFields.contains(field)
            ? Colors.mainRed : Colors.gray700
        cell.contentConfiguration = configuration
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch fields[indexPath.row] {
        case .dateFormat:
            presentPicker(
                title: "import.mapping.field.dateFormat".localized,
                options: viewModel.availableDateFormats.map { ($0.pattern, $0) },
                onPick: { [weak self] in self?.viewModel.setDateFormat($0) })
        case .signConvention:
            presentPicker(
                title: "import.mapping.field.sign".localized,
                options: viewModel.availableSignConventions.map {
                    (ImportMappingViewModel.describe($0), $0)
                },
                onPick: { [weak self] in self?.viewModel.setSignConvention($0) })
        case .dateColumn:
            presentColumnPicker(for: .date)
        case .descriptionColumn:
            presentColumnPicker(for: .description)
        case .amountColumn:
            presentColumnPicker(for: .amount)
        }
    }

    private func presentPicker<T>(
        title: String, options: [(String, T)], onPick: @escaping (T) -> Void
    ) {
        let sheet = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        for (label, value) in options {
            sheet.addAction(UIAlertAction(title: label, style: .default) { _ in onPick(value) })
        }
        sheet.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel))
        anchorAndPresent(sheet)
    }

    private func presentColumnPicker(for role: ColumnRole) {
        let options = (0..<viewModel.columnCount).map { index -> (String, Int) in
            let sample = viewModel.sampleValues(forColumn: index)
            let label = sample.isEmpty
                ? String(format: "import.mapping.column.number".localized, index + 1)
                : "\(index + 1): \(sample)"
            return (label, index)
        }
        presentPicker(
            title: "import.mapping.column.pick".localized,
            options: options,
            onPick: { [weak self] index in self?.viewModel.setColumn(index, to: role) })
    }

    private func anchorAndPresent(_ alert: UIAlertController) {
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        present(alert, animated: true)
    }
}
