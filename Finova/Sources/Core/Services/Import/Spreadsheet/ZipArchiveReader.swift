//
//  ZipArchiveReader.swift
//  Finova
//
//  Just enough ZIP to open a spreadsheet.
//
//  Foundation has no unzip API, and pulling in a third-party archiver for this would be a large
//  dependency for a small need. What an `.xlsx` requires is narrow: locate a handful of named entries
//  and inflate them. That is the central directory plus raw DEFLATE, and the `Compression` framework
//  already provides the second half.
//
//  Read via the CENTRAL DIRECTORY rather than by scanning local file headers. The local header may
//  carry zero sizes with the real values in a trailing data descriptor — common in streamed archives —
//  and a scanner that trusts it reads garbage. The central directory is always authoritative.
//

import Compression
import Foundation

struct ZipArchiveReader {

    private let data: Data
    private var entries: [String: Entry] = [:]

    private struct Entry {
        let compressionMethod: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    /// Refuses absurd expansions rather than inflating a zip bomb into memory.
    private static let maxEntryBytes = 64 * 1_048_576

    init?(data: Data) {
        self.data = data
        guard data.count > 22, let directoryStart = Self.findCentralDirectory(in: data) else {
            return nil
        }
        guard let parsed = Self.parseCentralDirectory(in: data, from: directoryStart) else {
            return nil
        }
        self.entries = parsed
        guard !entries.isEmpty else { return nil }
    }

    var entryNames: [String] { Array(entries.keys) }

    func contains(_ name: String) -> Bool { entries[name] != nil }

    /// The inflated contents of one entry.
    func extract(_ name: String) -> Data? {
        guard let entry = entries[name] else { return nil }
        guard entry.uncompressedSize <= Self.maxEntryBytes else { return nil }

        // The local header's variable-length fields have to be skipped to find the payload; their
        // lengths differ from the central directory's, so they must be read here rather than reused.
        let headerOffset = entry.localHeaderOffset
        guard headerOffset + 30 <= data.count else { return nil }
        guard readUInt32(at: headerOffset) == 0x0403_4B50 else { return nil }

        let nameLength = Int(readUInt16(at: headerOffset + 26))
        let extraLength = Int(readUInt16(at: headerOffset + 28))
        let payloadStart = headerOffset + 30 + nameLength + extraLength
        guard payloadStart + entry.compressedSize <= data.count else { return nil }

        let payload = data.subdata(in: payloadStart..<(payloadStart + entry.compressedSize))

        switch entry.compressionMethod {
        case 0:
            return payload                       // stored
        case 8:
            return inflate(payload, expecting: entry.uncompressedSize)
        default:
            return nil                           // bzip2, LZMA and friends: not worth supporting here
        }
    }

    // MARK: - DEFLATE

    private func inflate(_ payload: Data, expecting size: Int) -> Data? {
        guard size > 0 else { return Data() }
        // A little headroom: a stored-but-marked-deflate entry can decode slightly larger.
        let capacity = max(size, 1) + 1024
        var output = Data(count: capacity)

        let written: Int = output.withUnsafeMutableBytes { destination in
            payload.withUnsafeBytes { source in
                guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress,
                      let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                // COMPRESSION_ZLIB is raw DEFLATE here, which is exactly what a ZIP entry stores.
                return compression_decode_buffer(
                    destinationBase, capacity, sourceBase, payload.count, nil, COMPRESSION_ZLIB)
            }
        }

        guard written > 0 else { return nil }
        return output.prefix(written)
    }

    // MARK: - Central directory

    private static func findCentralDirectory(in data: Data) -> Int? {
        // The end-of-central-directory record is last, but a trailing comment can follow it, so scan
        // backwards over the maximum comment length rather than assuming it sits at the very end.
        let signature: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
        let searchLimit = min(data.count, 65_536 + 22)
        let start = data.count - searchLimit

        var index = data.count - 22
        while index >= start {
            if data[index] == signature[0], data[index + 1] == signature[1],
               data[index + 2] == signature[2], data[index + 3] == signature[3] {
                let offset = Int(data.readUInt32(at: index + 16))
                return offset < data.count ? offset : nil
            }
            index -= 1
        }
        return nil
    }

    private static func parseCentralDirectory(in data: Data, from start: Int) -> [String: Entry]? {
        var entries: [String: Entry] = [:]
        var offset = start

        while offset + 46 <= data.count, data.readUInt32(at: offset) == 0x0201_4B50 {
            let method = data.readUInt16(at: offset + 10)
            let compressedSize = Int(data.readUInt32(at: offset + 20))
            let uncompressedSize = Int(data.readUInt32(at: offset + 24))
            let nameLength = Int(data.readUInt16(at: offset + 28))
            let extraLength = Int(data.readUInt16(at: offset + 30))
            let commentLength = Int(data.readUInt16(at: offset + 32))
            let localOffset = Int(data.readUInt32(at: offset + 42))

            let nameStart = offset + 46
            guard nameStart + nameLength <= data.count else { break }
            let name = String(
                data: data.subdata(in: nameStart..<(nameStart + nameLength)), encoding: .utf8)
                ?? String(
                    data: data.subdata(in: nameStart..<(nameStart + nameLength)), encoding: .isoLatin1)

            if let name, !name.hasSuffix("/") {
                entries[name] = Entry(
                    compressionMethod: method,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localOffset)
            }

            offset = nameStart + nameLength + extraLength + commentLength
        }

        return entries.isEmpty ? nil : entries
    }

    private func readUInt16(at offset: Int) -> UInt16 { data.readUInt16(at: offset) }
    private func readUInt32(at offset: Int) -> UInt32 { data.readUInt32(at: offset) }
}

extension Data {
    /// Little-endian reads, bounds-checked. ZIP and BIFF are both little-endian throughout.
    func readUInt16(at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { return 0 }
        return UInt16(self[startIndex + offset]) | (UInt16(self[startIndex + offset + 1]) << 8)
    }

    func readUInt32(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        return UInt32(self[startIndex + offset])
            | (UInt32(self[startIndex + offset + 1]) << 8)
            | (UInt32(self[startIndex + offset + 2]) << 16)
            | (UInt32(self[startIndex + offset + 3]) << 24)
    }
}
