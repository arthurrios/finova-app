//
//  ImportMappingViewModel.swift
//  Finova
//
//  Shown only when inference could not settle something structural. Everything here is a correction
//  to a guess the engine already made, never a blank form — the user should be confirming, not
//  configuring.
//

import Foundation

final class ImportMappingViewModel {

    enum Field: CaseIterable {
        case dateFormat
        case signConvention
        case dateColumn
        case descriptionColumn
        case amountColumn

        var title: String {
            switch self {
            case .dateFormat: return "import.mapping.field.dateFormat".localized
            case .signConvention: return "import.mapping.field.sign".localized
            case .dateColumn: return "import.mapping.field.dateColumn".localized
            case .descriptionColumn: return "import.mapping.field.descriptionColumn".localized
            case .amountColumn: return "import.mapping.field.amountColumn".localized
            }
        }
    }

    var onSchemaUpdated: (() -> Void)?
    var onError: ((String) -> Void)?
    var onReplanned: ((ImportPlan) -> Void)?

    private(set) var schema: ResolvedSchema
    let file: LoadedFile
    private let originalPlan: ImportPlan
    private let transactionRepo: TransactionRepository
    private let batchRepo: ImportBatchRepository

    init(
        file: LoadedFile,
        plan: ImportPlan,
        transactionRepo: TransactionRepository = TransactionRepository(),
        batchRepo: ImportBatchRepository = ImportBatchRepository()
    ) {
        self.file = file
        self.originalPlan = plan
        self.schema = plan.schema
        self.transactionRepo = transactionRepo
        self.batchRepo = batchRepo
    }

    /// The aspects inference was least sure about, so the UI can draw attention to them.
    var weakFields: Set<Field> {
        var result: Set<Field> = []
        if originalPlan.confidence.dateFormat.score < 0.6 { result.insert(.dateFormat) }
        if originalPlan.confidence.signConvention.score < 0.6 { result.insert(.signConvention) }
        if originalPlan.confidence.columnRoles.score < 0.6 {
            result.formUnion([.dateColumn, .descriptionColumn, .amountColumn])
        }
        return result
    }

    var columnCount: Int {
        originalPlan.rows.first?.rawCells.count ?? schema.roles.count
    }

    /// A few real values from a column, so the user can tell which one they are looking at.
    func sampleValues(forColumn index: Int, limit: Int = 3) -> String {
        originalPlan.rows
            .prefix(limit)
            .compactMap { $0.rawCells[safe: index] }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    func value(for field: Field) -> String {
        switch field {
        case .dateFormat:
            return schema.dateFormat.pattern
        case .signConvention:
            return Self.describe(schema.signConvention)
        case .dateColumn:
            return columnLabel(schema.column(for: .date))
        case .descriptionColumn:
            return columnLabel(schema.column(for: .description))
        case .amountColumn:
            return columnLabel(schema.column(for: .amount) ?? schema.column(for: .debit))
        }
    }

    private func columnLabel(_ index: Int?) -> String {
        guard let index else { return "import.mapping.column.none".localized }
        let sample = sampleValues(forColumn: index, limit: 1)
        return sample.isEmpty
            ? String(format: "import.mapping.column.number".localized, index + 1)
            : "\(index + 1): \(sample)"
    }

    static func describe(_ convention: SignConvention) -> String {
        switch convention {
        case .negativeIsExpense: return "import.mapping.sign.negativeIsExpense".localized
        case .positiveIsExpense: return "import.mapping.sign.positiveIsExpense".localized
        case .separateDebitCredit: return "import.mapping.sign.separateColumns".localized
        case .indicatorColumn: return "import.mapping.sign.indicatorColumn".localized
        }
    }

    // MARK: - Editing

    func setDateFormat(_ spec: DateFormatSpec) {
        schema.dateFormat = spec
        onSchemaUpdated?()
    }

    func setSignConvention(_ convention: SignConvention) {
        schema.signConvention = convention
        onSchemaUpdated?()
    }

    func setColumn(_ index: Int, to role: ColumnRole) {
        // A role is single-occupancy: assigning it here has to clear it wherever it was.
        for (existing, assigned) in schema.roles where assigned == role && existing != index {
            schema.roles[existing] = .ignored
        }
        schema.roles[index] = role
        onSchemaUpdated?()
    }

    var availableDateFormats: [DateFormatSpec] { DateFormatSpec.candidates }

    var availableSignConventions: [SignConvention] {
        [.negativeIsExpense, .positiveIsExpense, .separateDebitCredit, .indicatorColumn]
    }

    // MARK: - Confirm

    func confirm() {
        guard schema.isUsable else {
            onError?("import.mapping.error.incomplete".localized)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let existing = self.transactionRepo.fetchAllTransactions()
            let alreadyImported = self.batchRepo.importedRowFingerprints()

            do {
                let plan = try CSVImportEngine.replan(
                    CSVImportEngine.Input(
                        filename: self.file.displayName, data: self.file.data,
                        alreadyImported: alreadyImported, existing: existing),
                    schema: self.schema)
                DispatchQueue.main.async { self.onReplanned?(plan) }
            } catch {
                DispatchQueue.main.async {
                    self.onError?((error as? ImportError)?.userMessage
                        ?? "import.error.cannotRead".localized)
                }
            }
        }
    }
}
