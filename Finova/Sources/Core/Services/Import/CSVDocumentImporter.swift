//
//  CSVDocumentImporter.swift
//  Finova
//
//  Getting the bytes. The one genuinely untestable part of the feature, kept as thin as possible.
//

import UIKit
import UniformTypeIdentifiers

struct LoadedFile {
    let displayName: String
    let byteCount: Int
    let sha256: String
    let data: Data
}

@MainActor
final class CSVDocumentImporter: NSObject {

    /// `.data` is in the list because banks mislabel CSV exports as `public.data` and would otherwise
    /// be unselectable. The cost is that a PDF can be picked; validation is by CONTENT, never by
    /// declared type, so that lands as a clear "this isn't text" rather than as garbage rows.
    static let acceptedTypes: [UTType] = [
        .commaSeparatedText, .tabSeparatedText, .plainText, .text, .data,
    ]

    private var completion: ((Result<LoadedFile, ImportError>) -> Void)?

    func present(
        from presenter: UIViewController,
        completion: @escaping (Result<LoadedFile, ImportError>) -> Void
    ) {
        self.completion = completion

        // `asCopy: true` is the important argument. UIKit hands back a URL in our own container, so
        // there is no security-scoped resource to balance, and — the part that actually bites — an
        // iCloud Drive file that is not downloaded locally gets materialised by the system first.
        // With `asCopy: false` that same file reads as zero bytes with no error at all, which reaches
        // the user as "the import did nothing".
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: Self.acceptedTypes, asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        presenter.present(picker, animated: true)
    }
}

extension CSVDocumentImporter: UIDocumentPickerDelegate {

    func documentPicker(
        _ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]
    ) {
        guard let url = urls.first else {
            completion?(.failure(.cannotReadFile))
            return
        }

        do {
            let data = try Data(contentsOf: url)
            // Everything downstream works on `Data`; no URL escapes this type, so there is no
            // lifetime to get wrong.
            defer { try? FileManager.default.removeItem(at: url) }

            guard !data.isEmpty else {
                completion?(.failure(.emptyFile))
                return
            }
            guard data.count <= CSVImportEngine.maxFileBytes else {
                completion?(.failure(.fileTooLarge(
                    bytes: data.count, limit: CSVImportEngine.maxFileBytes)))
                return
            }

            completion?(.success(LoadedFile(
                displayName: url.lastPathComponent,
                byteCount: data.count,
                sha256: CSVImportEngine.sha256(of: data),
                data: data)))
        } catch {
            logError("[Import] Could not read picked file: \(error)")
            completion?(.failure(.cannotReadFile))
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion?(.failure(.cancelled))
    }
}
