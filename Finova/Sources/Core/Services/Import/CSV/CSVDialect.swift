//
//  CSVDialect.swift
//  Finova
//
//  How one particular file spells "CSV".
//

import Foundation

struct CSVDialect: Equatable, Codable {
    let delimiter: Character
    let quote: Character

    /// The candidates, in the order the sniffer scores them. Semicolon leads because it is what
    /// every Brazilian bank emits — a comma cannot be the delimiter in a locale where it is also the
    /// decimal separator.
    static let candidateDelimiters: [Character] = [";", ",", "\t", "|"]

    static let comma = CSVDialect(delimiter: ",", quote: "\"")
    static let semicolon = CSVDialect(delimiter: ";", quote: "\"")
    static let tab = CSVDialect(delimiter: "\t", quote: "\"")

    init(delimiter: Character, quote: Character = "\"") {
        self.delimiter = delimiter
        self.quote = quote
    }

    // Character isn't Codable, so the wire form is the string spelling.
    private enum CodingKeys: String, CodingKey { case delimiter, quote }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = try c.decode(String.self, forKey: .delimiter)
        let q = try c.decode(String.self, forKey: .quote)
        self.delimiter = d.first ?? ","
        self.quote = q.first ?? "\""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(String(delimiter), forKey: .delimiter)
        try c.encode(String(quote), forKey: .quote)
    }

    var displayName: String {
        switch delimiter {
        case ";": return ";"
        case ",": return ","
        case "\t": return "tab"
        default: return String(delimiter)
        }
    }
}
