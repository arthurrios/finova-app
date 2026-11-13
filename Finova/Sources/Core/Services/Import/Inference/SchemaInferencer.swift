//
//  SchemaInferencer.swift
//  Finova
//
//  Works out what a file's columns mean.
//
//  Keyword matching on headers is the obvious approach and it is not enough: headers are localized,
//  abbreviated, sometimes absent, and banks rename them without notice. So the heavy lifting is done
//  by two CONTENT proofs that need no vocabulary at all:
//
//  * Mutual exclusivity identifies a split debit/credit pair — two numeric columns where practically
//    every row fills exactly one.
//  * The balance proof identifies the amount column AND the sign convention together: if
//    `balance[i] - balance[i-1]` equals `amount[i]` across the file, that is arithmetic, not a guess.
//
//  Keywords then break ties and label the rest.
//

import Foundation

struct ColumnProfile {
    let index: Int
    let headerText: String?
    let values: [String]
    let emptyRate: Double
    let distinctRatio: Double
    let dateHitRate: Double
    let numericHitRate: Double
    let negativeRate: Double
    let meanTokenCount: Double
    let letterRate: Double
    /// Values are drawn from a tiny set like {D, C} or {+, -}.
    let looksLikeDirectionFlag: Bool
}

enum SchemaInferencer {

    struct Result {
        let schema: ResolvedSchema
        let confidence: InferenceConfidence
        let profiles: [ColumnProfile]
        /// The rows that are actual data, preamble and header already removed.
        let dataRows: [CSVTokenizer.Row]
        let headerRow: CSVTokenizer.Row?
    }

    // MARK: - Header keywords (accent- and case-folded before matching)

    private static let keywords: [ColumnRole: [String]] = [
        .date: ["data", "data lancamento", "data movimento", "data da compra", "dt", "dt lancamento",
                "date", "posted", "posted date", "transaction date", "booking date"],
        .description: ["descricao", "historico", "lancamento", "detalhes", "estabelecimento",
                       "titulo", "description", "memo", "details", "payee", "merchant", "narrative"],
        .amount: ["valor", "valor r$", "valor (r$)", "montante", "quantia", "amount", "value",
                  "transaction amount"],
        .debit: ["debito", "saida", "saidas", "pagamento", "debit", "withdrawal", "money out",
                 "paid out"],
        .credit: ["credito", "entrada", "entradas", "recebimento", "credit", "deposit", "money in",
                  "paid in"],
        .balance: ["saldo", "saldo atual", "balance", "running balance"],
        .category: ["categoria", "category", "tipo de transacao"],
        .docId: ["documento", "doc", "num doc", "numero do documento", "identificador", "id",
                 "reference", "transaction id"],
        .directionFlag: ["d/c", "dc", "tipo", "natureza", "debito/credito"],
    ]

    // MARK: - Entry point

    static func infer(rows: [CSVTokenizer.Row]) -> Result? {
        guard !rows.isEmpty else { return nil }

        let (modalCount, _) = CSVTokenizer.modalFieldCount(rows)
        guard modalCount >= 2 else { return nil }

        // Preamble and summary lines are exactly the rows that disagree with the modal width.
        let shaped = rows.filter { $0.cells.count == modalCount }
        guard !shaped.isEmpty else { return nil }
        let preambleRows = rows.prefix(while: { $0.cells.count != modalCount }).count

        let headerDetection = detectHeader(in: shaped, columnCount: modalCount)
        let headerRow = headerDetection.hasHeader ? shaped.first : nil
        let dataRows = headerDetection.hasHeader ? Array(shaped.dropFirst()) : shaped
        guard !dataRows.isEmpty else { return nil }

        let profiles = (0..<modalCount).map { index in
            profile(index: index, header: headerRow?.cells[safe: index], rows: dataRows)
        }

        var confidence = InferenceConfidence(
            header: headerDetection.confidence,
            dateFormat: .none("not yet resolved"),
            numberFormat: .none("not yet resolved"),
            amountShape: .none("not yet resolved"),
            signConvention: .none("not yet resolved"),
            columnRoles: .none("not yet resolved"))

        var roles: [Int: ColumnRole] = [:]

        // 1. Date. Content first — a column that parses as dates in every row is a date column
        //    whatever it is called.
        //
        // A file where no column reads as dates is NOT a failure to report: it is a file the user has
        // to map by hand. Returning nil here dead-ended the import in an alert; instead the roles are
        // left unassigned and the confidence stays at zero, which routes the caller to the mapping
        // screen — the screen that exists for exactly this case.
        let dateColumn = pickDateColumn(profiles)
        let dateIndex = dateColumn?.index
        let dateIsFused = dateColumn?.isFused ?? false
        if let dateIndex { roles[dateIndex] = .date }

        var dateFormat = DateFormatSpec(pattern: "dd/MM/yyyy")
        if let dateIndex {
            // For a fused column the format has to be detected from the extracted PREFIXES; feeding
            // it the whole `15/07/2026 14:30 COMPRA MERCADO` field would match nothing.
            let dateValues = dateIsFused
                ? DateFieldParser.leadingDateTexts(in: profiles[dateIndex].values)
                : profiles[dateIndex].values
            switch DateFieldParser.detectFormat(in: dateValues) {
            case .proven(let spec):
                dateFormat = spec
                confidence.dateFormat = .proof("a component above 12 fixes the order")
            case .likely(let spec, _):
                dateFormat = spec
                confidence.dateFormat = .strong("dates run in order under this reading")
            case .ambiguous(let first, _):
                dateFormat = first
                confidence.dateFormat = .weak("every component is 12 or less — day and month are interchangeable")
            case .inconsistent, .none:
                confidence.dateFormat = .none("the dates in this column contradict each other")
            }
        } else {
            confidence.dateFormat = .none("no column reads as dates")
        }

        // 2. The amount shape.
        let numericColumns = profiles
            .filter { $0.index != dateIndex && $0.numericHitRate >= 0.8 }
            .sorted { $0.index < $1.index }

        let shape = resolveAmountShape(numericColumns: numericColumns, profiles: profiles)
        for (index, role) in shape.roles { roles[index] = role }
        confidence.amountShape = shape.confidence
        confidence.signConvention = shape.signConfidence

        // As with the date above: no identifiable amount column is a mapping problem, not a fatal one.
        // The schema comes back unusable and the caller sends the user to the mapping screen.
        let foundAnAmount = shape.roles.values.contains(.amount)
            || shape.roles.values.contains(.debit)
            || shape.roles.values.contains(.credit)

        // 3. Number format, decided across every numeric column that carries money.
        let moneyValues = shape.roles
            .filter { $0.value == .amount || $0.value == .debit || $0.value == .credit }
            .flatMap { profiles[$0.key].values }
        let (numberFormat, numberProven) = AmountParser.detectFormat(in: moneyValues)
        if !foundAnAmount {
            confidence.numberFormat = .none("no column reads as amounts")
        } else {
            confidence.numberFormat = numberProven
                ? .proof("a value carries both separators, so the order is fixed")
                : .weak("no value carries both separators — the decimal mark is inferred")
        }

        // 4. Description: the wordiest unassigned column. Skipped when the date column already
        //    carries it — the remainder after the date IS the description.
        if !dateIsFused,
           let descriptionIndex = pickDescriptionColumn(profiles, taken: Set(roles.keys)) {
            roles[descriptionIndex] = .description
        }

        // 5. Everything else by keyword only — these are hints, and a wrong guess costs nothing.
        for profile in profiles where roles[profile.index] == nil {
            roles[profile.index] = keywordRole(for: profile) ?? .ignored
        }

        if dateIsFused {
            confidence.columnRoles = .strong("the date and description share one column")
        } else {
            confidence.columnRoles = roles.values.contains(.description)
                ? .strong("a date, an amount and a description were all identified")
                : .weak("no description column — titles will fall back to the payment rail")
        }

        let schema = ResolvedSchema(
            roles: roles,
            hasHeaderRow: headerDetection.hasHeader,
            preambleRows: preambleRows,
            dateFormat: dateFormat,
            numberFormat: numberFormat,
            signConvention: shape.signConvention,
            dateColumnCarriesDescription: dateIsFused,
            bankPresetId: nil)

        return Result(schema: schema, confidence: confidence, profiles: profiles,
                      dataRows: dataRows, headerRow: headerRow)
    }

    // MARK: - Header

    private static func detectHeader(
        in rows: [CSVTokenizer.Row], columnCount: Int
    ) -> (hasHeader: Bool, confidence: SubConfidence) {
        guard let first = rows.first, rows.count >= 2 else {
            return (false, .weak("too few rows to tell"))
        }

        let cells = first.cells
        let allNonEmpty = cells.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let allDistinct = Set(cells.map { $0.normalizedForSearch() }).count == cells.count
        let noDates = cells.allSatisfy { DateFieldParser.dateHitRate(in: [$0]) == 0 }
        let noNumbers = cells.allSatisfy { (try? AmountParser.parse($0, format: .ptBR)) == nil }

        // A header row is text where the rows below are data. All four conditions matter: a data row
        // can be all-distinct, and a header can contain a number-ish code, but not both at once.
        let isHeader = allNonEmpty && allDistinct && noDates && noNumbers
        guard isHeader else {
            return (false, .strong("the first row parses as data, so there is no header"))
        }

        // Corroborate with keywords: a header we also recognise is worth more than one we merely
        // failed to parse as data.
        let recognised = cells.filter { cell in
            let folded = cell.normalizedForSearch()
            return keywords.values.contains { list in list.contains { folded.contains($0) } }
        }.count

        return recognised >= 2
            ? (true, .proof("the first row is text and names columns we recognise"))
            : (true, .strong("the first row is text where the rows below are data"))
    }

    // MARK: - Profiling

    private static func profile(index: Int, header: String?, rows: [CSVTokenizer.Row]) -> ColumnProfile {
        let values = rows.map { $0.cells[safe: index] ?? "" }
        let nonEmpty = values.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let total = Double(max(values.count, 1))

        let numericCount = nonEmpty.filter { (try? AmountParser.parse($0, format: .ptBR)) != nil }.count
        let negatives = nonEmpty.compactMap { try? AmountParser.parse($0, format: .ptBR) }
            .filter { $0.cents < 0 }.count
        let letters = nonEmpty.filter { $0.contains(where: \.isLetter) }.count
        let tokens = nonEmpty.map { Double($0.split(separator: " ").count) }
        let flagValues = Set(nonEmpty.map { $0.uppercased().trimmingCharacters(in: .whitespaces) })

        return ColumnProfile(
            index: index,
            headerText: header,
            values: values,
            emptyRate: 1 - Double(nonEmpty.count) / total,
            distinctRatio: Double(Set(nonEmpty).count) / Double(max(nonEmpty.count, 1)),
            dateHitRate: DateFieldParser.dateHitRate(in: nonEmpty),
            numericHitRate: nonEmpty.isEmpty ? 0 : Double(numericCount) / Double(nonEmpty.count),
            negativeRate: numericCount == 0 ? 0 : Double(negatives) / Double(numericCount),
            meanTokenCount: tokens.isEmpty ? 0 : tokens.reduce(0, +) / Double(tokens.count),
            letterRate: nonEmpty.isEmpty ? 0 : Double(letters) / Double(nonEmpty.count),
            looksLikeDirectionFlag: !flagValues.isEmpty && flagValues.count <= 3
                && flagValues.allSatisfy { ["D", "C", "+", "-", "DEBITO", "CREDITO"].contains($0) }
        )
    }

    // MARK: - Column selection

    /// The date column, and whether it also carries the description.
    ///
    /// A column of clean dates always wins. Only when nothing qualifies does this look for a column
    /// whose values BEGIN with a date — the fused "Lançamentos" shape — because that probe is the
    /// most expensive one in inference and would otherwise run on every file.
    private static func pickDateColumn(_ profiles: [ColumnProfile]) -> (index: Int, isFused: Bool)? {
        if let clean = profiles
            .filter({ $0.dateHitRate >= 0.9 })
            .max(by: { scoreForDate($0) < scoreForDate($1) }) {
            return (clean.index, false)
        }

        let fused = profiles
            .map { ($0, DateFieldParser.leadingDateHitRate(in: $0.values)) }
            .filter { $0.1 >= 0.9 }
            .max(by: { $0.1 < $1.1 })
        return fused.map { ($0.0.index, true) }
    }

    private static func scoreForDate(_ profile: ColumnProfile) -> Double {
        var score = profile.dateHitRate
        if let header = profile.headerText?.normalizedForSearch(),
           keywords[.date]?.contains(where: { header.contains($0) }) == true {
            score += 0.5
        }
        // Ties break toward the leftmost column: when a file carries both a posting date and a
        // transaction date, the first is the one the bank leads with.
        score -= Double(profile.index) * 0.001
        return score
    }

    private static func pickDescriptionColumn(_ profiles: [ColumnProfile], taken: Set<Int>) -> Int? {
        profiles
            .filter { !taken.contains($0.index) && $0.letterRate >= 0.5 && $0.emptyRate < 0.5 }
            .max(by: { scoreForDescription($0) < scoreForDescription($1) })?
            .index
    }

    private static func scoreForDescription(_ profile: ColumnProfile) -> Double {
        var score = profile.letterRate + min(profile.meanTokenCount / 4, 1.0) + profile.distinctRatio
        if let header = profile.headerText?.normalizedForSearch(),
           keywords[.description]?.contains(where: { header.contains($0) }) == true {
            score += 1.5
        }
        return score
    }

    private static func keywordRole(for profile: ColumnProfile) -> ColumnRole? {
        if profile.looksLikeDirectionFlag { return .directionFlag }
        guard let header = profile.headerText?.normalizedForSearch(), !header.isEmpty else { return nil }
        // Longest match wins, so "saldo atual" beats "saldo" and "data lancamento" beats "data".
        var best: (role: ColumnRole, length: Int)?
        for (role, list) in keywords {
            for keyword in list where header.contains(keyword) {
                if best == nil || keyword.count > best!.length { best = (role, keyword.count) }
            }
        }
        return best?.role
    }

    // MARK: - Amount shape and sign convention

    private struct AmountShape {
        let roles: [Int: ColumnRole]
        let signConvention: SignConvention
        let confidence: SubConfidence
        let signConfidence: SubConfidence
    }

    private static func resolveAmountShape(
        numericColumns: [ColumnProfile], profiles: [ColumnProfile]
    ) -> AmountShape {
        // A. A split debit/credit pair. Mutual exclusivity is a much better signal than any keyword,
        //    and it works on unlabeled files.
        if let pair = findMutuallyExclusivePair(numericColumns) {
            let debitFirst = isDebitColumn(pair.a) || isCreditColumn(pair.b)
            let debit = debitFirst ? pair.a : pair.b
            let credit = debitFirst ? pair.b : pair.a
            return AmountShape(
                roles: [debit.index: .debit, credit.index: .credit],
                signConvention: .separateDebitCredit,
                confidence: .proof("two columns where each row fills exactly one"),
                signConfidence: .proof("direction is which column the value is in"))
        }

        // B. A balance column proves which of two numeric columns is the amount — and which way the
        //    signs run — by arithmetic.
        if let proof = findBalanceProof(numericColumns) {
            var roles: [Int: ColumnRole] = [proof.amount.index: .amount, proof.balance.index: .balance]
            if let flag = profiles.first(where: \.looksLikeDirectionFlag) {
                roles[flag.index] = .directionFlag
            }
            return AmountShape(
                roles: roles,
                signConvention: proof.positiveIsIncome ? .negativeIsExpense : .positiveIsExpense,
                confidence: .proof("the running balance moves by exactly this column's value"),
                signConfidence: .proof("the balance rises when this column is positive"))
        }

        // C. A D/C indicator column alongside a single amount.
        if let flag = profiles.first(where: \.looksLikeDirectionFlag),
           let amount = numericColumns.first(where: { !isBalanceColumn($0) }) {
            return AmountShape(
                roles: [amount.index: .amount, flag.index: .directionFlag],
                signConvention: .indicatorColumn,
                confidence: .strong("one amount column beside a debit/credit marker"),
                signConfidence: .proof("direction is stated per row"))
        }

        // D. One amount column, and nothing proves which way it runs.
        let candidates = numericColumns.filter { !isBalanceColumn($0) }
        guard let amount = candidates.max(by: { scoreForAmount($0) < scoreForAmount($1) }) else {
            return AmountShape(roles: [:], signConvention: .negativeIsExpense,
                               confidence: .none("no numeric column"),
                               signConfidence: .none("no numeric column"))
        }

        var roles: [Int: ColumnRole] = [amount.index: .amount]
        for profile in numericColumns where profile.index != amount.index && isBalanceColumn(profile) {
            roles[profile.index] = .balance
        }

        let folded = amount.headerText?.normalizedForSearch() ?? ""
        let named = !folded.isEmpty && (keywords[.amount]?.contains { folded.contains($0) } ?? false)

        // Deliberately NOT inferred from "most rows are negative". In a current account most rows
        // ARE debits, so the majority sign carries no information — and getting it backwards inverts
        // an entire month of the user's ledger. Assume the common convention, score it low, and let
        // the review screen be the check.
        return AmountShape(
            roles: roles,
            signConvention: .negativeIsExpense,
            confidence: named
                ? .strong("a single column named as the amount")
                : .weak("a single numeric column, identified by content"),
            signConfidence: .weak("nothing in the file proves which sign means money out"))
    }

    /// Two numeric columns where practically every row fills exactly one.
    private static func findMutuallyExclusivePair(
        _ columns: [ColumnProfile]
    ) -> (a: ColumnProfile, b: ColumnProfile)? {
        guard columns.count >= 2 else { return nil }
        for i in 0..<columns.count {
            for j in (i + 1)..<columns.count {
                let a = columns[i], b = columns[j]
                let rowCount = min(a.values.count, b.values.count)
                guard rowCount >= 4 else { continue }

                var exclusive = 0
                for row in 0..<rowCount {
                    let aFilled = isNonZeroNumber(a.values[row])
                    let bFilled = isNonZeroNumber(b.values[row])
                    if aFilled != bFilled { exclusive += 1 }
                }
                if Double(exclusive) / Double(rowCount) >= 0.9 { return (a, b) }
            }
        }
        return nil
    }

    /// Finds a (amount, balance) pair where the balance moves by the amount each row.
    private static func findBalanceProof(
        _ columns: [ColumnProfile]
    ) -> (amount: ColumnProfile, balance: ColumnProfile, positiveIsIncome: Bool)? {
        guard columns.count >= 2 else { return nil }

        for candidateBalance in columns {
            for candidateAmount in columns where candidateAmount.index != candidateBalance.index {
                let balances = candidateBalance.values.map { try? AmountParser.parse($0, format: .ptBR) }
                let amounts = candidateAmount.values.map { try? AmountParser.parse($0, format: .ptBR) }
                // Three rows give two consecutive deltas, which is the minimum the check below needs.
                // This gate has to stay in step with the `comparable` threshold further down —
                // leaving it at 4 while that said 2 silently disabled the proof on short files, and
                // an unproven sign convention parks every row for a decision.
                let rowCount = min(balances.count, amounts.count)
                guard rowCount >= 3 else { continue }

                var agreeing = 0, opposing = 0, comparable = 0
                for row in 1..<rowCount {
                    guard let previous = balances[row - 1], let current = balances[row],
                          let amount = amounts[row] else { continue }
                    comparable += 1
                    let delta = current.cents - previous.cents
                    if delta == amount.cents { agreeing += 1 }
                    else if delta == -amount.cents { opposing += 1 }
                }
                // Two consecutive deltas agreeing to the exact cent is already arithmetic, not
                // coincidence, and short files are common — a single month of a low-traffic account,
                // or the tail of a filtered export. Demanding four rows meant those files fell
                // through to "the sign cannot be proven" and parked every row for a decision.
                guard comparable >= 2 else { continue }

                if Double(agreeing) / Double(comparable) >= 0.8 {
                    return (candidateAmount, candidateBalance, true)
                }
                if Double(opposing) / Double(comparable) >= 0.8 {
                    return (candidateAmount, candidateBalance, false)
                }
            }
        }
        return nil
    }

    private static func isNonZeroNumber(_ value: String) -> Bool {
        guard let parsed = try? AmountParser.parse(value, format: .ptBR) else { return false }
        return parsed.cents != 0
    }

    private static func isBalanceColumn(_ profile: ColumnProfile) -> Bool {
        guard let header = profile.headerText?.normalizedForSearch() else { return false }
        return keywords[.balance]?.contains(where: { header.contains($0) }) ?? false
    }

    private static func isDebitColumn(_ profile: ColumnProfile) -> Bool {
        guard let header = profile.headerText?.normalizedForSearch() else { return false }
        return keywords[.debit]?.contains(where: { header.contains($0) }) ?? false
    }

    private static func isCreditColumn(_ profile: ColumnProfile) -> Bool {
        guard let header = profile.headerText?.normalizedForSearch() else { return false }
        return keywords[.credit]?.contains(where: { header.contains($0) }) ?? false
    }

    private static func scoreForAmount(_ profile: ColumnProfile) -> Double {
        var score = profile.numericHitRate
        if let header = profile.headerText?.normalizedForSearch(),
           keywords[.amount]?.contains(where: { header.contains($0) }) == true {
            score += 1.0
        }
        // A column that never goes negative and never varies much is more likely a balance or a
        // document number than a transaction amount.
        if profile.negativeRate > 0 { score += 0.3 }
        return score
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
