//
//  EncodingSniffer.swift
//  Finova
//
//  Bytes to text, for files nobody validated.
//
//  The order below is the whole design, and it is not the order that comes naturally. The tempting
//  version is "try UTF-8, fall back to Latin-1". That is wrong, and wrong in a way that is silent and
//  permanent: Latin-1 NEVER fails, because all 256 byte values are valid characters in it. So a
//  genuinely UTF-8 Brazilian export with one corrupt byte fails strict UTF-8, decodes "successfully"
//  as Latin-1, and every accented character in the file becomes mojibake — "São Paulo" imports as
//  "SÃ£o Paulo" and stays that way in the user's ledger forever.
//
//  So before falling back, we MEASURE how UTF-8-shaped the bytes are. A file that is 99% valid UTF-8
//  is a UTF-8 file with damage, and decoding it lossily loses one character. Decoding it as Latin-1
//  loses every accented word in it.
//

import Foundation

enum EncodingSniffer {

    struct Result {
        let text: String
        let encoding: String.Encoding
        /// True when the text was recovered with replacement characters. Worth surfacing: it means
        /// the file is damaged, and the user should be told before the rows land.
        let wasLossy: Bool
    }

    /// A file at least this UTF-8-shaped is treated as UTF-8 with damage rather than another encoding.
    private static let utf8ConfidenceThreshold = 0.99

    static func decode(_ data: Data) -> Result? {
        guard !data.isEmpty else { return nil }

        // 1. A byte-order mark is proof, not evidence. Stop here.
        if let bom = decodeByteOrderMark(data) { return bom }

        // 2. Strict UTF-8. The overwhelmingly common case, and free.
        if let text = String(data: data, encoding: .utf8) {
            return Result(text: stripBOM(text), encoding: .utf8, wasLossy: false)
        }

        // 3. Not strictly valid — but how close? See the header for why this step exists.
        if utf8Validity(of: data) >= utf8ConfidenceThreshold {
            let repaired = String(decoding: data, as: UTF8.self)  // lossy: inserts U+FFFD
            return Result(text: stripBOM(repaired), encoding: .utf8, wasLossy: true)
        }

        // 4. Genuinely a single-byte encoding. Windows-1252 before ISO Latin-1: it is a superset for
        //    the printable range, and it is what Excel on Windows writes.
        for encoding in [String.Encoding.windowsCP1252, .isoLatin1] {
            guard let text = String(data: data, encoding: encoding) else { continue }
            // Last guard against getting it backwards: this signature means we just read UTF-8 bytes
            // as single-byte characters.
            if looksLikeMisreadUTF8(text) {
                return Result(text: stripBOM(String(decoding: data, as: UTF8.self)),
                              encoding: .utf8, wasLossy: true)
            }
            return Result(text: stripBOM(text), encoding: encoding, wasLossy: false)
        }

        return nil
    }

    // MARK: - Byte-order marks

    private static func decodeByteOrderMark(_ data: Data) -> Result? {
        let bytes = [UInt8](data.prefix(4))

        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            let body = data.dropFirst(3)
            let text = String(data: body, encoding: .utf8)
            return Result(text: text ?? String(decoding: body, as: UTF8.self),
                          encoding: .utf8, wasLossy: text == nil)
        }
        // UTF-32 marks start with the same two bytes as UTF-16, so they have to be ruled out first.
        if bytes.starts(with: [0xFF, 0xFE, 0x00, 0x00]) || bytes.starts(with: [0x00, 0x00, 0xFE, 0xFF]) {
            return String(data: data, encoding: .utf32)
                .map { Result(text: $0, encoding: .utf32, wasLossy: false) }
        }
        if bytes.starts(with: [0xFF, 0xFE]) {
            return String(data: data, encoding: .utf16LittleEndian)
                .map { Result(text: stripBOM($0), encoding: .utf16LittleEndian, wasLossy: false) }
        }
        if bytes.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16BigEndian)
                .map { Result(text: stripBOM($0), encoding: .utf16BigEndian, wasLossy: false) }
        }
        return nil
    }

    /// A BOM decoded as content becomes U+FEFF glued to the first header cell, which then matches no
    /// keyword and silently costs you the first column.
    private static func stripBOM(_ text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }

    // MARK: - UTF-8 shape

    /// The fraction of multi-byte sequence starts that are followed by well-formed continuation
    /// bytes. Pure ASCII scores 1.0 (nothing to get wrong); random Latin-1 text with accents scores
    /// close to 0, because `é` (0xE9) in Latin-1 is a 3-byte-sequence lead in UTF-8 and is almost
    /// never followed by two continuation bytes.
    static func utf8Validity(of data: Data) -> Double {
        let bytes = [UInt8](data)
        var sequences = 0
        var valid = 0
        var i = 0

        while i < bytes.count {
            let b = bytes[i]
            if b < 0x80 { i += 1; continue }          // ASCII

            let width: Int
            switch b {
            case 0xC2...0xDF: width = 2
            case 0xE0...0xEF: width = 3
            case 0xF0...0xF4: width = 4
            default:
                // 0x80...0xC1 and 0xF5+ can never start a sequence.
                sequences += 1
                i += 1
                continue
            }

            sequences += 1
            let end = i + width
            if end <= bytes.count, (1..<width).allSatisfy({ bytes[i + $0] & 0xC0 == 0x80 }) {
                valid += 1
                i = end
            } else {
                i += 1
            }
        }

        // No high bytes at all: pure ASCII, which is valid UTF-8 by definition.
        return sequences == 0 ? 1.0 : Double(valid) / Double(sequences)
    }

    /// The mojibake signature: `Ã` or `Â` immediately followed by a Latin-1 supplement character.
    /// That pair is what UTF-8 bytes look like when read one byte at a time, and it is vanishingly
    /// rare in real text.
    static func looksLikeMisreadUTF8(_ text: String) -> Bool {
        var previous: Character?
        for character in text {
            if let previous, previous == "Ã" || previous == "Â",
               let scalar = character.unicodeScalars.first,
               (0xA0...0xBF).contains(scalar.value) || (0x80...0x9F).contains(scalar.value) {
                return true
            }
            previous = character
        }
        return false
    }
}
