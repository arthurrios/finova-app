//
//  CloudKitErrorHandler.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import CloudKit

final class CloudKitErrorHandler {
    static func shouldRetry(_ error: Error) -> (Bool, TimeInterval?) {
        guard let ckError = error as? CKError else { return (false, nil) }
        switch ckError.code {
        case .networkUnavailable, .networkFailure:
            return (true, 5.0)
        case .serviceUnavailable, .requestRateLimited:
            let retryAfter = ckError.retryAfterSeconds ?? 10.0
            return (true, retryAfter)
        case .zoneBusy:
            return (true, 3.0)
        case .quotaExceeded:
            return (false, nil)
        default:
            return (false, nil)
        }
    }
}
