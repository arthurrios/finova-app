//
//  XLSReader.swift
//  Finova
//
//  Legacy `.xls` — the format most Brazilian banks still hand out — into rows of strings.
//
//  Two nested formats, and both have to be unpicked:
//
//  1. OLE2 / Compound File Binary Format. The file is a little filesystem: a header, a FAT describing
//     sector chains, and a directory of named streams. The spreadsheet lives in a stream called
//     "Workbook" (or "Book" on very old files). Streams below a size threshold live in a separate
//     MINI-FAT packed inside another stream, which is the part naive implementations miss.
//  2. BIFF8. The workbook stream is a flat sequence of `(type, length, payload)` records. Text is
//     pooled in an SST record, numbers appear as NUMBER or the space-saving RK encoding, and dates
//     are numbers wearing a date-shaped format from the XF table.
//
//  Deliberately read-only, deliberately partial: enough record types to recover a bank statement, and
//  an honest error for anything else. Encrypted workbooks (FILEPASS) are refused outright rather than
//  yielding plausible nonsense.
//

import Foundation

enum XLSReader: SpreadsheetReader {

    static func canRead(_ data: Data) -> Bool {
        FileFormatSniffer.detect(data) == .ole2Document
    }

    static func read(_ data: Data) throws -> [CSVTokenizer.Row] {
        guard let container = OLE2Container(data: data) else {
            throw SpreadsheetError.corrupt("not a readable compound document")
        }
        guard let workbook = container.stream(named: "Workbook") ?? container.stream(named: "Book") else {
            throw SpreadsheetError.notAWorkbook
        }
        return try BIFFWorkbook.rows(from: workbook)
    }
}

// MARK: - OLE2 compound document

struct OLE2Container {

    private let data: Data
    private let sectorSize: Int
    private let miniSectorSize: Int
    private var fat: [UInt32] = []
    private var miniFAT: [UInt32] = []
    private var directory: [(name: String, start: UInt32, size: Int, isStream: Bool)] = []
    private var miniStream = Data()

    /// Streams smaller than this live in the mini-FAT rather than the main one.
    private static let miniStreamCutoff = 4096
    private static let endOfChain: UInt32 = 0xFFFF_FFFE
    private static let freeSector: UInt32 = 0xFFFF_FFFF

    init?(data: Data) {
        guard data.count >= 512 else { return nil }
        guard [UInt8](data.prefix(8)) == [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1] else {
            return nil
        }
        self.data = data
        self.sectorSize = 1 << Int(data.readUInt16(at: 30))
        self.miniSectorSize = 1 << Int(data.readUInt16(at: 32))
        guard sectorSize >= 512, sectorSize <= 65_536, miniSectorSize >= 64 else { return nil }

        guard buildFAT(), buildDirectory() else { return nil }
        buildMiniStream()
    }

    /// The contents of a named stream.
    func stream(named name: String) -> Data? {
        guard let entry = directory.first(where: { $0.isStream && $0.name == name }) else { return nil }
        if entry.size < Self.miniStreamCutoff {
            return readChain(from: entry.start, in: miniStream, sectorSize: miniSectorSize,
                             fat: miniFAT, limit: entry.size)
        }
        return readSectorChain(from: entry.start, limit: entry.size)
    }

    // MARK: - Structure

    private mutating func buildFAT() -> Bool {
        let fatSectorCount = Int(data.readUInt32(at: 44))
        guard fatSectorCount > 0, fatSectorCount < 65_536 else { return false }

        // The first 109 FAT sector pointers live in the header; beyond that they continue in DIFAT
        // sectors. A bank statement never gets near that, so the header block is enough.
        var sectors: [UInt32] = []
        for index in 0..<min(fatSectorCount, 109) {
            sectors.append(data.readUInt32(at: 76 + index * 4))
        }

        for sector in sectors where sector != Self.freeSector {
            guard let block = sectorData(sector) else { continue }
            for offset in stride(from: 0, to: block.count, by: 4) {
                fat.append(block.readUInt32(at: offset))
            }
        }
        return !fat.isEmpty
    }

    private mutating func buildDirectory() -> Bool {
        let directoryStart = data.readUInt32(at: 48)
        guard let directoryData = readSectorChain(from: directoryStart, limit: Int.max) else {
            return false
        }

        // Each directory entry is exactly 128 bytes: a UTF-16 name, a type byte, then the stream's
        // starting sector and size.
        var offset = 0
        while offset + 128 <= directoryData.count {
            let nameLength = Int(directoryData.readUInt16(at: offset + 64))
            let type = directoryData[directoryData.startIndex + offset + 66]

            if nameLength > 2, nameLength <= 64 {
                let nameBytes = directoryData.subdata(
                    in: (offset)..<(offset + nameLength - 2))   // trailing UTF-16 NUL
                let name = String(data: nameBytes, encoding: .utf16LittleEndian) ?? ""
                let start = directoryData.readUInt32(at: offset + 116)
                let size = Int(directoryData.readUInt32(at: offset + 120))
                directory.append((name: name, start: start, size: size, isStream: type == 2))
            }
            offset += 128
        }
        return !directory.isEmpty
    }

    private mutating func buildMiniStream() {
        // The mini-FAT's own chain, then the root entry's stream which holds the mini sectors.
        let miniFATStart = data.readUInt32(at: 60)
        if let miniFATData = readSectorChain(from: miniFATStart, limit: Int.max) {
            for offset in stride(from: 0, to: miniFATData.count, by: 4) {
                miniFAT.append(miniFATData.readUInt32(at: offset))
            }
        }
        if let root = directory.first(where: { !$0.isStream }) {
            miniStream = readSectorChain(from: root.start, limit: root.size) ?? Data()
        }
    }

    // MARK: - Chains

    private func sectorData(_ sector: UInt32) -> Data? {
        let offset = 512 + Int(sector) * sectorSize
        guard offset >= 0, offset + sectorSize <= data.count else { return nil }
        return data.subdata(in: offset..<(offset + sectorSize))
    }

    private func readSectorChain(from start: UInt32, limit: Int) -> Data? {
        var result = Data()
        var sector = start
        var guardCount = 0

        while sector != Self.endOfChain, sector != Self.freeSector, guardCount < 1_048_576 {
            guard let block = sectorData(sector) else { break }
            result.append(block)
            if result.count >= limit { break }
            guard Int(sector) < fat.count else { break }
            sector = fat[Int(sector)]
            guardCount += 1
        }

        guard !result.isEmpty else { return nil }
        return limit == Int.max ? result : result.prefix(limit)
    }

    private func readChain(
        from start: UInt32, in source: Data, sectorSize: Int, fat: [UInt32], limit: Int
    ) -> Data? {
        var result = Data()
        var sector = start
        var guardCount = 0

        while sector != Self.endOfChain, sector != Self.freeSector, guardCount < 1_048_576 {
            let offset = Int(sector) * sectorSize
            guard offset + sectorSize <= source.count else { break }
            result.append(source.subdata(in: offset..<(offset + sectorSize)))
            if result.count >= limit { break }
            guard Int(sector) < fat.count else { break }
            sector = fat[Int(sector)]
            guardCount += 1
        }

        guard !result.isEmpty else { return nil }
        return result.prefix(limit)
    }
}

// MARK: - BIFF8

enum BIFFWorkbook {

    private enum Record: UInt16 {
        case bof = 0x0809
        case eof = 0x000A
        case sst = 0x00FC
        case continueRecord = 0x003C
        case labelSST = 0x00FD
        case label = 0x0204
        case number = 0x0203
        case rk = 0x027E
        case mulRK = 0x00BD
        case formula = 0x0006
        case string = 0x0207
        case blank = 0x0201
        case mulBlank = 0x00BE
        case boolErr = 0x0205
        case xf = 0x00E0
        case format = 0x041E
        case filePass = 0x002F
    }

    static func rows(from stream: Data) throws -> [CSVTokenizer.Row] {
        var sharedStrings: [String] = []
        var xfFormatIds: [Int] = []
        var customDateFormats: Set<Int> = []
        var cells: [Int: [Int: String]] = [:]   // row → column → display string

        var offset = 0
        var lastSSTRange: Range<Int>?

        while offset + 4 <= stream.count {
            let type = stream.readUInt16(at: offset)
            let length = Int(stream.readUInt16(at: offset + 2))
            let bodyStart = offset + 4
            guard bodyStart + length <= stream.count else { break }
            let body = stream.subdata(in: bodyStart..<(bodyStart + length))

            switch Record(rawValue: type) {
            case .filePass:
                // Encrypted. Refuse rather than emit convincing nonsense.
                throw SpreadsheetError.unsupportedFormat("encrypted")

            case .sst:
                // The SST is continued by CONTINUE records, and the segment boundaries are
                // SIGNIFICANT — they must NOT be concatenated away. When a string spans a boundary,
                // the continuation begins with its own option byte declaring whether the REMAINDER of
                // that string is 8- or 16-bit. Splicing the payloads together and parsing the result
                // as one buffer swallows those bytes as if they were text, and every string past the
                // first boundary decodes as garbage — which on a real statement is almost all of them.
                var segments: [Data] = [body]
                var scan = bodyStart + length
                while scan + 4 <= stream.count, stream.readUInt16(at: scan) == Record.continueRecord.rawValue {
                    let continueLength = Int(stream.readUInt16(at: scan + 2))
                    guard scan + 4 + continueLength <= stream.count else { break }
                    segments.append(stream.subdata(in: (scan + 4)..<(scan + 4 + continueLength)))
                    scan += 4 + continueLength
                }
                sharedStrings = parseSST(segments: segments)
                lastSSTRange = bodyStart..<scan
                offset = scan
                continue

            case .format:
                if body.count > 2 {
                    let formatId = Int(body.readUInt16(at: 0))
                    if let code = parseUnicodeString(body, at: 2)?.value, looksTemporal(code) {
                        customDateFormats.insert(formatId)
                    }
                }

            case .xf:
                if body.count >= 4 { xfFormatIds.append(Int(body.readUInt16(at: 2))) }

            case .labelSST:
                if body.count >= 10 {
                    let row = Int(body.readUInt16(at: 0)), column = Int(body.readUInt16(at: 2))
                    let index = Int(body.readUInt32(at: 6))
                    if sharedStrings.indices.contains(index) {
                        cells[row, default: [:]][column] = sharedStrings[index]
                    }
                }

            case .label:
                if body.count >= 8, let text = parseUnicodeString(body, at: 6)?.value {
                    cells[Int(body.readUInt16(at: 0)), default: [:]][Int(body.readUInt16(at: 2))] = text
                }

            case .number:
                if body.count >= 14 {
                    let row = Int(body.readUInt16(at: 0)), column = Int(body.readUInt16(at: 2))
                    let xf = Int(body.readUInt16(at: 4))
                    let value = Double(bitPattern: body.readUInt64(at: 6))
                    cells[row, default: [:]][column] = render(
                        value, xf: xf, xfFormatIds: xfFormatIds, customDateFormats: customDateFormats)
                }

            case .rk:
                if body.count >= 10 {
                    let row = Int(body.readUInt16(at: 0)), column = Int(body.readUInt16(at: 2))
                    let xf = Int(body.readUInt16(at: 4))
                    let value = decodeRK(body.readUInt32(at: 6))
                    cells[row, default: [:]][column] = render(
                        value, xf: xf, xfFormatIds: xfFormatIds, customDateFormats: customDateFormats)
                }

            case .mulRK:
                // One record carrying a run of adjacent RK cells: (xf, rk) pairs between the first
                // column and a trailing last-column field.
                if body.count >= 6 {
                    let row = Int(body.readUInt16(at: 0))
                    let firstColumn = Int(body.readUInt16(at: 2))
                    let pairCount = (body.count - 6) / 6
                    for pair in 0..<pairCount {
                        let base = 4 + pair * 6
                        let xf = Int(body.readUInt16(at: base))
                        let value = decodeRK(body.readUInt32(at: base + 2))
                        cells[row, default: [:]][firstColumn + pair] = render(
                            value, xf: xf, xfFormatIds: xfFormatIds,
                            customDateFormats: customDateFormats)
                    }
                }

            case .formula:
                // A formula's cached result: a number here, or a following STRING record for text.
                if body.count >= 14 {
                    let row = Int(body.readUInt16(at: 0)), column = Int(body.readUInt16(at: 2))
                    let xf = Int(body.readUInt16(at: 4))
                    let bits = body.readUInt64(at: 6)
                    // The "special value" marker: top 16 bits all set means the result is not a number.
                    if (bits >> 48) != 0xFFFF {
                        cells[row, default: [:]][column] = render(
                            Double(bitPattern: bits), xf: xf, xfFormatIds: xfFormatIds,
                            customDateFormats: customDateFormats)
                    }
                }

            default:
                break
            }

            offset = bodyStart + length
            if let range = lastSSTRange, offset < range.upperBound { offset = range.upperBound }
        }

        guard !cells.isEmpty else { throw SpreadsheetError.emptyWorkbook }
        return assemble(cells)
    }

    // MARK: - Assembly

    private static func assemble(_ cells: [Int: [Int: String]]) -> [CSVTokenizer.Row] {
        let orderedRows = cells.keys.sorted()
        var result: [CSVTokenizer.Row] = []

        for row in orderedRows {
            guard let columns = cells[row], let highest = columns.keys.max() else { continue }
            let values = (0...highest).map { columns[$0] ?? "" }
            // Row indices are 0-based in BIFF; +1 makes the reported line match what the user sees.
            result.append(CSVTokenizer.Row(line: row + 1, cells: values))
        }
        return result
    }

    // MARK: - Values

    /// RK packs a number into 32 bits: two flag bits, then either a truncated IEEE double or a
    /// 30-bit integer, optionally divided by 100.
    private static func decodeRK(_ raw: UInt32) -> Double {
        let isInteger = (raw & 0x02) != 0
        let isDivided = (raw & 0x01) != 0
        var value: Double

        if isInteger {
            value = Double(Int32(bitPattern: raw & 0xFFFF_FFFC) >> 2)
        } else {
            value = Double(bitPattern: UInt64(raw & 0xFFFF_FFFC) << 32)
        }
        return isDivided ? value / 100 : value
    }

    private static func render(
        _ value: Double, xf: Int, xfFormatIds: [Int], customDateFormats: Set<Int>
    ) -> String {
        let builtInDateFormats: Set<Int> = Set(14...22).union(Set(45...47))
        let formatId = xfFormatIds.indices.contains(xf) ? xfFormatIds[xf] : 0

        if builtInDateFormats.contains(formatId) || customDateFormats.contains(formatId) {
            let hasTime = value != value.rounded(.down)
            if let rendered = SpreadsheetCell.displayString(
                forExcelSerial: value, includesTime: hasTime) {
                return rendered
            }
        }
        return SpreadsheetCell.displayString(forNumber: value)
    }

    private static func looksTemporal(_ code: String) -> Bool {
        var inQuotes = false
        for character in code {
            if character == "\"" { inQuotes.toggle(); continue }
            guard !inQuotes else { continue }
            if "yYmMdDhHsS".contains(character) { return true }
        }
        return false
    }

    // MARK: - Strings

    /// The shared string table, read across its CONTINUE segments.
    ///
    /// Segment boundaries carry meaning here, which is why this walks a cursor over the segments
    /// rather than over one spliced buffer: a string that runs past the end of a segment resumes in
    /// the next one AFTER a fresh option byte, and that byte can flip the encoding of the remainder
    /// from 8-bit to 16-bit or back mid-word.
    static func parseSST(segments: [Data]) -> [String] {
        guard let header = segments.first, header.count >= 8 else { return [] }
        let uniqueCount = Int(header.readUInt32(at: 4))
        guard uniqueCount > 0, uniqueCount < 1_048_576 else { return [] }

        var cursor = SSTCursor(segments: segments, segmentIndex: 0, offset: 8)
        var strings: [String] = []

        while strings.count < uniqueCount, let value = cursor.readString() {
            strings.append(value)
        }
        return strings
    }

    /// A byte cursor over the SST's segments that understands continuation semantics.
    private struct SSTCursor {
        let segments: [Data]
        var segmentIndex: Int
        var offset: Int

        private var currentSegment: Data? {
            segments.indices.contains(segmentIndex) ? segments[segmentIndex] : nil
        }

        private var remainingInSegment: Int {
            guard let segment = currentSegment else { return 0 }
            return max(0, segment.count - offset)
        }

        /// Steps to the next segment. `consumingOptionByte` is true only when a STRING is resuming —
        /// other data continues without one.
        private mutating func advanceSegment(consumingOptionByte: Bool) -> UInt8? {
            segmentIndex += 1
            offset = 0
            guard let segment = currentSegment, !segment.isEmpty else { return nil }
            guard consumingOptionByte else { return 0 }
            let option = segment[segment.startIndex]
            offset = 1
            return option
        }

        private mutating func readByte() -> UInt8? {
            if remainingInSegment == 0, advanceSegment(consumingOptionByte: false) == nil { return nil }
            guard let segment = currentSegment, remainingInSegment > 0 else { return nil }
            let byte = segment[segment.startIndex + offset]
            offset += 1
            return byte
        }

        private mutating func readUInt16() -> UInt16? {
            guard let low = readByte(), let high = readByte() else { return nil }
            return UInt16(low) | (UInt16(high) << 8)
        }

        private mutating func readUInt32() -> UInt32? {
            guard let a = readUInt16(), let b = readUInt16() else { return nil }
            return UInt32(a) | (UInt32(b) << 16)
        }

        private mutating func skip(_ count: Int) {
            var remaining = count
            while remaining > 0 {
                if remainingInSegment == 0 {
                    if advanceSegment(consumingOptionByte: false) == nil { return }
                    continue
                }
                let step = min(remaining, remainingInSegment)
                offset += step
                remaining -= step
            }
        }

        /// One XLUnicodeString, resuming across segments as needed.
        mutating func readString() -> String? {
            guard let characterCount = readUInt16().map(Int.init), let options = readByte() else {
                return nil
            }
            var isWide = (options & 0x01) != 0
            let hasFarEast = (options & 0x04) != 0
            let hasFormatting = (options & 0x08) != 0

            var formattingRuns = 0
            var farEastLength = 0
            if hasFormatting { formattingRuns = Int(readUInt16() ?? 0) }
            if hasFarEast { farEastLength = Int(readUInt32() ?? 0) }

            var units: [UInt16] = []
            units.reserveCapacity(characterCount)
            var read = 0

            while read < characterCount {
                // Characters are never split across a boundary by Excel, so running out of room means
                // the string resumes in the next segment — behind a fresh option byte.
                if remainingInSegment == 0 || (isWide && remainingInSegment < 2) {
                    guard let option = advanceSegment(consumingOptionByte: true) else { break }
                    isWide = (option & 0x01) != 0
                    continue
                }
                if isWide {
                    guard let unit = readUInt16() else { break }
                    units.append(unit)
                } else {
                    guard let byte = readByte() else { break }
                    // The 8-bit form is Latin-1, so a byte maps straight to its code point.
                    units.append(UInt16(byte))
                }
                read += 1
            }

            skip(formattingRuns * 4 + farEastLength)
            return String(decoding: units, as: UTF16.self)
        }
    }

    /// A BIFF8 XLUnicodeString: 16-bit character count, an options byte, then the characters.
    private static func parseUnicodeString(_ data: Data, at start: Int) -> (value: String, nextOffset: Int)? {
        guard start + 3 <= data.count else { return nil }
        let characterCount = Int(data.readUInt16(at: start))
        let options = data[data.startIndex + start + 2]
        let isWide = (options & 0x01) != 0
        let hasFarEast = (options & 0x04) != 0
        let hasFormatting = (options & 0x08) != 0

        var offset = start + 3
        var formattingRuns = 0
        var farEastLength = 0
        if hasFormatting, offset + 2 <= data.count {
            formattingRuns = Int(data.readUInt16(at: offset)); offset += 2
        }
        if hasFarEast, offset + 4 <= data.count {
            farEastLength = Int(data.readUInt32(at: offset)); offset += 4
        }

        let byteCount = isWide ? characterCount * 2 : characterCount
        guard offset + byteCount <= data.count else { return nil }
        let raw = data.subdata(in: offset..<(offset + byteCount))
        let value = isWide
            ? (String(data: raw, encoding: .utf16LittleEndian) ?? "")
            : String(raw.map { Character(UnicodeScalar($0)) })

        // Formatting runs are 4 bytes each; the phonetic block trails everything.
        let next = offset + byteCount + formattingRuns * 4 + farEastLength
        return (value, next)
    }
}

extension Data {
    func readUInt64(at offset: Int) -> UInt64 {
        guard offset >= 0, offset + 8 <= count else { return 0 }
        var result: UInt64 = 0
        for index in 0..<8 {
            result |= UInt64(self[startIndex + offset + index]) << (8 * index)
        }
        return result
    }
}
