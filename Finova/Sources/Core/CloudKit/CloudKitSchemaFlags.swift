//
//  CloudKitSchemaFlags.swift
//  Finova
//

/// Gates record fields whose CloudKit schema has not been deployed to production yet.
///
/// CloudKit auto-creates unknown record fields in the DEVELOPMENT environment but refuses them in
/// production. The server rejects the entire record —
///
///     Cannot create or modify field 'earlyPaymentSchema' in record 'Transaction' in production schema
///
/// — and `SyncEngine.pushBatches` stops all remaining save batches on a schema error. So a single
/// undeployed field does not degrade one feature, it halts syncing for everything: unrelated edits sit
/// pending forever and get overwritten by the next pull.
///
/// Ship order is therefore: deploy the schema in the CloudKit Dashboard
/// (Development → Deploy Schema Changes → Production), *then* flip the flag.
enum CloudKitSchemaFlags {
    /// Whether `earlyPaymentSchema`, `settledByTransactionUuid`, `isEarlyPayment`,
    /// `cancelledByTransactionUuid` and `isCancellationRefund` exist in the production schema.
    ///
    /// While this is `false`, early payment and cancellation work correctly on the device that
    /// performs them, but the pointers do not travel. A second device keeps showing those
    /// installments as still owed and would let the user pay or cancel them again — so this must be
    /// `true` before the feature reaches users on more than one device.
    ///
    /// Deployed to the production schema on 2026-08-01. Setting this back to `false` is the escape
    /// hatch if a field turns out to be missing: sync keeps working, only the pointers stop syncing.
    static let installmentPointerFieldsDeployed = true
}
