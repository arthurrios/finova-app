//
//  FileFormatSniffer.swift
//  Finova
//
//  What a file ACTUALLY is, by its leading bytes.
//
//  The document picker has to accept `public.data`, because banks routinely serve CSV exports under
//  a generic type and would otherwise be unselectable. The cost is that any file at all can be
//  chosen — and a spreadsheet or PDF fed to a CSV parser produces line noise, not an error. Every
//  downstream failure then describes a symptom ("no date and amount columns") instead of the cause
//  ("this is an Excel file"), which sends the user hunting in entirely the wrong place.
//
//  Magic bytes are checked BEFORE decoding, so the diagnosis is exact rather than inferred from
//  mojibake.
//

import Foundation

enum DetectedFileFormat: Equatable {
    /// A ZIP container: .xlsx, .ods, .numbers — all of them spreadsheets in a zip.
    case zipContainer
    /// OLE2 compound document: legacy .xls (and .doc). What Brazilian banks most often hand out.
    case ole2Document
    case pdf
    case rtf
    /// Decodes as text but is dense with control characters — some other binary format.
    case otherBinary
    case text

    /// A name the user will recognise, for the error message.
    var displayName: String? {
        switch self {
        case .zipContainer: return "import.format.spreadsheet".localized
        case .ole2Document: return "import.format.excelLegacy".localized
        case .pdf: return "import.format.pdf".localized
        case .rtf: return "import.format.rtf".localized
        case .otherBinary: return "import.format.binary".localized
        case .text: return nil
        }
    }

    var isImportable: Bool { self == .text }
}

enum FileFormatSniffer {

    /// Bytes above which a file is treated as binary rather than text.
    ///
    /// NUL and most C0 controls never appear in a real CSV; tab, CR and LF obviously do. A few
    /// percent tolerance covers a stray control byte in an otherwise fine export.
    private static let binaryControlRatioThreshold = 0.02

    static func detect(_ data: Data) -> DetectedFileFormat {
        let head = [UInt8](data.prefix(8))

        // ZIP — xlsx/ods/numbers. "PK\u{03}\u{04}", or the empty/spanned variants.
        if head.starts(with: [0x50, 0x4B]) { return .zipContainer }
        // OLE2 compound document — legacy .xls.
        if head.starts(with: [0xD0, 0xCF, 0x11, 0xE0]) { return .ole2Document }
        if head.starts(with: Array("%PDF".utf8)) { return .pdf }
        if head.starts(with: Array("{\\rtf".utf8)) { return .rtf }

        // No signature we know. Fall back to measuring how much of it is control bytes, which
        // catches formats we have no magic for.
        let sample = data.prefix(4096)
        guard !sample.isEmpty else { return .text }
        let controls = sample.filter { byte in
            byte < 0x09 || (byte > 0x0D && byte < 0x20) || byte == 0x7F
        }.count
        let ratio = Double(controls) / Double(sample.count)
        return ratio > binaryControlRatioThreshold ? .otherBinary : .text
    }
}
