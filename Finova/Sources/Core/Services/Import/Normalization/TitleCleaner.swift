//
//  TitleCleaner.swift
//  Finova
//
//  Bank description lines into something a person would recognise in their ledger.
//
//  Everything stripped here is KEPT, on the side. The payment rail feeds categorization, the
//  installment marker is shown in the review even though v1 deliberately does not act on it, and the
//  raw string stays on the row so the UI can offer a one-tap revert. Deleting signal outright is how
//  you end up unable to explain what a row came from.
//

import Foundation

struct CleanedTitle: Equatable {
    let title: String
    let raw: String
    /// "PIX", "TED", "Débito automático" — the payment rail, which is a category signal but a poor
    /// title.
    let railHint: String?
    /// A `3/12` marker found in the description. Recorded and surfaced; NOT acted on, because
    /// creating real installment rows would hand inferred data to the series machinery.
    let installmentHint: InstallmentHint?
    /// A trailing document or authorisation number, removed from the title but retained so a row can
    /// still be traced back to the statement.
    let strippedDocId: String?
}

struct InstallmentHint: Equatable {
    let index: Int
    let total: Int
}

enum TitleCleaner {

    static let maxLength = 120

    /// Payment-rail prefixes, longest first so "Transferência enviada pelo Pix" wins over
    /// "Transferência". Matched accent- and case-insensitively.
    private static let railPrefixes: [(pattern: String, label: String)] = [
        ("transferencia enviada pelo pix", "PIX"),
        ("transferencia recebida pelo pix", "PIX"),
        ("transferencia enviada", "Transferência"),
        ("transferencia recebida", "Transferência"),
        ("pagamento de boleto", "Boleto"),
        ("compra com cartao de credito", "Crédito"),
        ("compra com cartao de debito", "Débito"),
        ("compra no debito", "Débito"),
        ("compra no credito", "Crédito"),
        ("debito automatico", "Débito automático"),
        ("pagamento efetuado", "Pagamento"),
        ("pix qrs", "PIX"),
        ("pix trf", "PIX"),
        ("pix enviado", "PIX"),
        ("pix recebido", "PIX"),
        ("saque", "Saque"),
        ("pagamento", "Pagamento"),
        ("boleto", "Boleto"),
        ("ted", "TED"),
        ("doc", "DOC"),
        ("pix", "PIX"),
    ]

    /// Tokens that must survive re-casing intact.
    private static let preservedTokens: Set<String> = [
        "PIX", "TED", "DOC", "CNPJ", "CPF", "S/A", "SA", "LTDA", "ME", "EPP", "IOF", "IPTU",
        "IPVA", "DARF", "FGTS", "INSS", "CEF", "BB", "ATM", "POS", "QR", "US", "UK", "TV", "CD",
    ]

    static func clean(_ raw: String) -> CleanedTitle {
        // NFC first. Files produced on macOS are NFD, so "Ação" arrives decomposed; without this the
        // same merchant in two files would fail to dedupe against itself.
        var text = raw.precomposedStringWithCanonicalMapping
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let original = text
        guard !text.isEmpty else {
            return CleanedTitle(title: "", raw: raw, railHint: nil,
                                installmentHint: nil, strippedDocId: nil)
        }

        // A leading date echo — Itaú repeats the day inside the description.
        text = text.replacingOccurrences(
            of: #"^\d{2}/\d{2}\s+"#, with: "", options: .regularExpression)

        let installmentHint = extractInstallmentHint(&text)
        let strippedDocId = extractDocumentId(&text)
        let railHint = extractRailPrefix(&text)

        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " -–—·•:,;/"))
        text = recase(text)

        if text.count > maxLength {
            text = String(text.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
        }

        // `title` is NOT NULL in the schema and is the primary dedupe key, so an empty result is not
        // an option. Fall back through progressively worse but non-empty choices.
        if text.isEmpty {
            text = railHint ?? strippedDocId ?? original
        }
        if text.isEmpty {
            text = "import.untitled".localized
        }

        return CleanedTitle(title: text, raw: raw, railHint: railHint,
                            installmentHint: installmentHint, strippedDocId: strippedDocId)
    }

    // MARK: - Extraction

    private static func extractInstallmentHint(_ text: inout String) -> InstallmentHint? {
        guard let regex = try? NSRegularExpression(pattern: #"\s+(\d{1,2})\s*/\s*(\d{1,2})\s*$"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let indexRange = Range(match.range(at: 1), in: text),
              let totalRange = Range(match.range(at: 2), in: text),
              let index = Int(text[indexRange]), let total = Int(text[totalRange]),
              total > 1, index >= 1, index <= total
        else { return nil }

        if let full = Range(match.range, in: text) { text.removeSubrange(full) }
        return InstallmentHint(index: index, total: total)
    }

    private static func extractDocumentId(_ text: inout String) -> String? {
        let patterns = [
            #"\s+(?:AUT|DOC|NSU|REF)\s*[:.]?\s*(\w{4,})\s*$"#,
            #"\s+(\d{6,})\s*$"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let captured = Range(match.range(at: 1), in: text)
            else { continue }
            let value = String(text[captured])
            if let full = Range(match.range, in: text) { text.removeSubrange(full) }
            return value
        }
        return nil
    }

    /// Connectors left dangling once a rail prefix is removed. "PAGAMENTO DE SALARIO" minus its rail
    /// is "DE SALARIO", which reads as a fragment; dropping the connector gives "Salario".
    private static let danglingConnectors = ["de ", "da ", "do ", "para ", "pelo ", "pela ", "em "]

    private static func extractRailPrefix(_ text: inout String) -> String? {
        let normalized = text.normalizedForSearch()
        for (pattern, label) in railPrefixes where normalized.hasPrefix(pattern) {
            // Drop by character count on the normalized form; folding is 1:1 for the Latin script
            // these prefixes are written in, so the offsets line up.
            text = String(text.dropFirst(pattern.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: " -–—:·•"))

            let remainder = text.normalizedForSearch()
            for connector in danglingConnectors where remainder.hasPrefix(connector) {
                // Only when something survives it — "Pagamento de" alone should keep its word.
                let stripped = String(text.dropFirst(connector.count))
                    .trimmingCharacters(in: .whitespaces)
                if !stripped.isEmpty { text = stripped }
                break
            }
            return label
        }
        return nil
    }

    // MARK: - Casing

    /// Re-cases only text that is essentially all-caps, and leaves short/known tokens alone.
    ///
    /// Bank descriptions are usually SHOUTED, and title-casing them is a real readability win. But
    /// blanket `.capitalized` turns "PIX" into "Pix" and "S/A" into "S/a", so acronyms are held back.
    static func recase(_ text: String) -> String {
        let letters = text.filter { $0.isLetter }
        guard !letters.isEmpty else { return text }
        let uppercaseRatio = Double(letters.filter { $0.isUppercase }.count) / Double(letters.count)
        guard uppercaseRatio >= 0.9 else { return text }

        return text.split(separator: " ", omittingEmptySubsequences: false)
            .map { word -> String in
                let plain = String(word)
                if preservedTokens.contains(plain.uppercased()) { return plain.uppercased() }
                // Anything with no lowercase potential — pure digits, codes — stays put.
                if plain.count <= 2 && plain.contains(where: \.isLetter) { return plain.uppercased() }
                if !plain.contains(where: \.isLetter) { return plain }
                return capitalizeFirstLetter(of: plain)
            }
            .joined(separator: " ")
    }

    /// Uppercases the first letter of a word and lowercases the rest.
    ///
    /// Not `String.capitalized`, which treats punctuation as a word boundary and so turns
    /// "NETFLIX.COM" into "Netflix.Com" and "APPLE.COM/BILL" into "Apple.Com/Bill". Domain names and
    /// merchant codes are extremely common in bank descriptions, so that is not a rare edge.
    private static func capitalizeFirstLetter(of word: String) -> String {
        let lowered = word.lowercased()
        guard let firstLetterIndex = lowered.firstIndex(where: \.isLetter) else { return lowered }
        return lowered.replacingCharacters(
            in: firstLetterIndex...firstLetterIndex,
            with: lowered[firstLetterIndex].uppercased())
    }
}
