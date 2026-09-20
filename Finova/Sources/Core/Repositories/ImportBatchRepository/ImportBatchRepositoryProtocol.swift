//
//  ImportBatchRepositoryProtocol.swift
//  Finova
//

import Foundation

protocol ImportBatchRepositoryProtocol: AnyObject {
    @discardableResult
    func create(_ batch: ImportBatch) throws -> ImportBatch
    func update(_ batch: ImportBatch) throws
    func fetch(uuid: String) -> ImportBatch?
    func history(limit: Int) -> [ImportBatch]
    func priorImports(ofFileHash hash: String) -> [ImportBatch]
    func recordRows(_ rows: [ImportBatchRow]) throws
    func importedRowFingerprints() -> Set<String>
    func liveTransactionCount(batchUuid: String) -> Int
    @discardableResult
    func reconcileInterrupted() -> [ImportBatch]
}
