//
//  XLSXReader.swift
//  Finova
//
//  `.xlsx` (and `.ods`, which is the same idea with a different schema) into rows of strings.
//
//  Three parts of the archive matter:
//
//  * `xl/sharedStrings.xml` — every text cell in the workbook is an INDEX into this table, not a
//    literal. Skip it and the sheet reads as a grid of integers.
//  * `xl/styles.xml` — a date cell is stored as a plain number. The only thing distinguishing
//    `45123` the amount from `45123` the date is the number format its style points at, so the style
//    table has to be resolved to know which is which.
//  * `xl/worksheets/sheetN.xml` — the grid itself, addressed as `A1`, `B7`. Cells that are empty are
//    simply ABSENT rather than blank, so column positions have to be reconstructed from the
//    reference; reading cells in document order silently shifts every value left.
//

import Foundation

enum XLSXReader: SpreadsheetReader {

    static func canRead(_ data: Data) -> Bool {
        guard data.count > 4, FileFormatSniffer.detect(data) == .zipContainer else { return false }
        guard let archive = ZipArchiveReader(data: data) else { return false }
        // Distinguishes a spreadsheet from any other zip (an .ods, a .docx, a plain archive).
        return archive.contains("[Content_Types].xml")
            && archive.entryNames.contains { $0.hasPrefix("xl/worksheets/") }
    }

    static func read(_ data: Data) throws -> [CSVTokenizer.Row] {
        guard let archive = ZipArchiveReader(data: data) else {
            throw SpreadsheetError.corrupt("not a readable archive")
        }

        let sharedStrings = archive.extract("xl/sharedStrings.xml").map(SharedStringsParser.parse) ?? []
        let dateStyles = archive.extract("xl/styles.xml").map(StylesParser.dateFormattedStyleIndices) ?? []

        // Sheets are named sheet1.xml, sheet2.xml… Sorted so "sheet2" doesn't precede "sheet10"
        // lexicographically and pick the wrong one.
        let sheetNames = archive.entryNames
            .filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }
            .sorted { lhs, rhs in
                (sheetNumber(lhs) ?? .max, lhs) < (sheetNumber(rhs) ?? .max, rhs)
            }
        guard !sheetNames.isEmpty else { throw SpreadsheetError.noSheets }

        // The first sheet that actually holds data — banks often lead with a cover or summary sheet.
        for name in sheetNames {
            guard let sheetData = archive.extract(name) else { continue }
            let rows = SheetParser.parse(
                sheetData, sharedStrings: sharedStrings, dateStyles: dateStyles)
            if rows.count >= 2 { return rows }
        }

        throw SpreadsheetError.emptyWorkbook
    }

    private static func sheetNumber(_ path: String) -> Int? {
        let digits = path.drop(while: { !$0.isNumber }).prefix(while: \.isNumber)
        return Int(digits)
    }
}

// MARK: - sharedStrings.xml

private enum SharedStringsParser {

    /// Every `<si>` becomes one string; its text may be split across several `<t>` runs when the cell
    /// carries mixed formatting, so the runs are concatenated rather than taking the first.
    static func parse(_ data: Data) -> [String] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.strings
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var strings: [String] = []
        private var current: String?
        private var capturing = false

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            if name == "si" { current = "" }
            if name == "t" { capturing = true }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if capturing { current? += string }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                    qualifiedName: String?) {
            if name == "t" { capturing = false }
            if name == "si" {
                strings.append(current ?? "")
                current = nil
            }
        }
    }
}

// MARK: - styles.xml

private enum StylesParser {

    /// Built-in numFmt ids that mean "this is a date or a time".
    ///
    /// 14–22 and 45–47 are the fixed date/time formats; anything custom gets an id of 164 or above and
    /// has to be recognised from its format CODE instead.
    private static let builtInDateFormats: Set<Int> = Set(14...22).union(Set(45...47))

    /// Indices into `cellXfs` whose number format is a date. Cell `s="3"` means "style 3".
    static func dateFormattedStyleIndices(_ data: Data) -> Set<Int> {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()

        var dateFormatIds = builtInDateFormats
        for (id, code) in delegate.customFormats where looksLikeADateFormat(code) {
            dateFormatIds.insert(id)
        }

        var result: Set<Int> = []
        for (index, formatId) in delegate.cellFormatIds.enumerated() where dateFormatIds.contains(formatId) {
            result.insert(index)
        }
        return result
    }

    /// A format code is a date format if it uses date tokens outside of quoted literal text.
    ///
    /// The quoting matters: `"y"0.00` is a currency format with a literal letter, not a year.
    private static func looksLikeADateFormat(_ code: String) -> Bool {
        var inQuotes = false
        for character in code {
            if character == "\"" { inQuotes.toggle(); continue }
            guard !inQuotes else { continue }
            if "yYmMdDhHsS".contains(character) {
                // `m` is minutes in a time format and months in a date one; either way it is temporal.
                return true
            }
        }
        return false
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var customFormats: [(Int, String)] = []
        var cellFormatIds: [Int] = []
        private var inCellXfs = false

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            switch name {
            case "numFmt":
                if let id = attributes["numFmtId"].flatMap(Int.init),
                   let code = attributes["formatCode"] {
                    customFormats.append((id, code))
                }
            case "cellXfs":
                inCellXfs = true
            case "xf" where inCellXfs:
                cellFormatIds.append(attributes["numFmtId"].flatMap(Int.init) ?? 0)
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                    qualifiedName: String?) {
            if name == "cellXfs" { inCellXfs = false }
        }
    }
}

// MARK: - worksheet XML

private enum SheetParser {

    static func parse(
        _ data: Data, sharedStrings: [String], dateStyles: Set<Int>
    ) -> [CSVTokenizer.Row] {
        let delegate = Delegate(sharedStrings: sharedStrings, dateStyles: dateStyles)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.rows
    }

    /// `"BC7"` → column index 54 (0-based). Empty cells are omitted from the XML entirely, so this is
    /// the only way to keep values in their real columns.
    static func columnIndex(fromReference reference: String) -> Int? {
        let letters = reference.prefix(while: { $0.isLetter })
        guard !letters.isEmpty else { return nil }
        var value = 0
        for character in letters.uppercased() {
            guard let ascii = character.asciiValue, ascii >= 65, ascii <= 90 else { return nil }
            value = value * 26 + Int(ascii - 64)
        }
        return value - 1
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        private let sharedStrings: [String]
        private let dateStyles: Set<Int>

        var rows: [CSVTokenizer.Row] = []
        private var lineNumber = 0

        private var currentCells: [Int: String] = [:]
        private var currentColumn = 0
        private var currentType: String?
        private var currentStyle: Int?
        private var buffer = ""
        private var capturing = false
        private var inInlineString = false

        init(sharedStrings: [String], dateStyles: Set<Int>) {
            self.sharedStrings = sharedStrings
            self.dateStyles = dateStyles
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            switch name {
            case "row":
                currentCells = [:]
                lineNumber += 1
            case "c":
                currentColumn = attributes["r"].flatMap(SheetParser.columnIndex(fromReference:))
                    ?? (currentCells.keys.max().map { $0 + 1 } ?? 0)
                currentType = attributes["t"]
                currentStyle = attributes["s"].flatMap(Int.init)
            case "v", "t":
                buffer = ""
                capturing = true
            case "is":
                inInlineString = true
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if capturing { buffer += string }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                    qualifiedName: String?) {
            switch name {
            case "v", "t":
                capturing = false
                if !buffer.isEmpty || currentCells[currentColumn] == nil {
                    currentCells[currentColumn] = resolve(buffer)
                }
            case "is":
                inInlineString = false
            case "row":
                emitRow()
            default:
                break
            }
        }

        /// Turns a raw cell payload into what the user would see in the spreadsheet.
        private func resolve(_ raw: String) -> String {
            // `t="s"` means the payload is an index into the shared string table.
            if currentType == "s", let index = Int(raw), sharedStrings.indices.contains(index) {
                return sharedStrings[index]
            }
            // Inline and formula-string cells carry their text directly.
            if currentType == "str" || currentType == "inlineStr" || inInlineString { return raw }
            if currentType == "b" { return raw == "1" ? "TRUE" : "FALSE" }

            guard let number = Double(raw) else { return raw }

            // A number whose style says "date" is a serial, not a quantity.
            if let style = currentStyle, dateStyles.contains(style) {
                let hasTime = number != number.rounded(.down)
                if let rendered = SpreadsheetCell.displayString(
                    forExcelSerial: number, includesTime: hasTime) {
                    return rendered
                }
            }
            return SpreadsheetCell.displayString(forNumber: number)
        }

        private func emitRow() {
            guard let highest = currentCells.keys.max() else {
                // A wholly empty row still occupies a line; keeping it preserves the file's shape for
                // preamble detection downstream.
                rows.append(CSVTokenizer.Row(line: lineNumber, cells: []))
                return
            }
            let cells = (0...highest).map { currentCells[$0] ?? "" }
            rows.append(CSVTokenizer.Row(line: lineNumber, cells: cells))
            currentCells = [:]
        }
    }
}
