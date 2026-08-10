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

    /// Whether the `AllocationTagBook` record type - fields `payload`, `updatedAt`, `userId` - exists in
    /// the production schema.
    ///
    /// **A whole record type, not just a field, so this is the stricter case of the warning above.**
    /// While `false`, allocation tags work exactly as they do today: they persist locally per account and
    /// simply do not travel between devices.
    ///
    /// Unlike the flags around it, flipping this one cannot halt anything else. The book is pushed and
    /// pulled on its own path rather than in `pushBatches`, so a schema rejection here stops tags
    /// travelling and leaves transactions, budgets and allocations syncing normally. That is what makes
    /// `true` a survivable mistake rather than an outage.
    ///
    /// Present in the **Development** schema as of 2026-08-04 (`payload` BYTES, `updatedAt` TIMESTAMP,
    /// `userId` STRING, with `___recordID` QUERYABLE, which is what the fetch-all query needs).
    ///
    /// **Not yet confirmed deployed to Production.** Xcode builds use the Development environment, so
    /// on-device testing works now. Before a TestFlight or App Store build: CloudKit Dashboard → Deploy
    /// Schema Changes → Production. Setting this back to `false` is the escape hatch if the deploy has
    /// not happened - tags stop travelling, nothing else changes.
    static let allocationTagBookDeployed = true

    /// Whether `businessDaySchema`, `businessDayRule`, `unadjustedDate` and `seriesPeriod` exist on
    /// the `Transaction` record in the production schema.
    ///
    /// Fields on an existing record type, so the warning above applies in full: these travel in
    /// `pushBatches`, and one undeployed field stops every remaining save batch.
    ///
    /// **`seriesPeriod` is the one that must not be missing.** It is which occurrence of a series a
    /// row is, as distinct from which month it counts in - the two diverge whenever a business-day
    /// rule moves a date across a month boundary. If it does not travel, a device that shifted an
    /// occurrence into the previous month and a peer reading only `budgetMonthDate` disagree about
    /// which occurrence the row is, the peer sees its slot as empty, and regeneration produces a
    /// duplicate. The other three are merely degraded without it; this one corrupts.
    ///
    /// Deployed to the production schema on 2026-08-04.
    static let businessDayFieldsDeployed = true

    /// Whether `statementPaymentUuid` and `isStatementPayment` exist on the `Transaction` record in
    /// the production schema.
    ///
    /// Fields on an existing record type pushed through `pushBatches`, so the warning at the top
    /// applies in full: one undeployed field halts every remaining save batch, for all data.
    ///
    /// While this is `false`, paying a statement works correctly on the device that does it — both
    /// rows are created and the invoice balance drops, because the rows themselves sync as ordinary
    /// transactions. Only the LINK between them stays local. A second device would show the debit and
    /// the credit as unrelated rows, and deleting one there would not remove the other. So this must
    /// be `true` before the feature reaches users on more than one device.
    ///
    /// It also gates the `earlyPaymentSchema` bump to 3: a receiver reads version 3 as "this sender
    /// knows about the statement-payment pointer", and claiming that while the field is withheld
    /// would make an absent pointer look like a deliberate clear.
    ///
    /// **Not yet deployed.** Xcode builds use the Development environment, where CloudKit
    /// auto-creates the fields, so on-device testing works with this `false` and the link simply
    /// stays local. Before a TestFlight or App Store build: CloudKit Dashboard → Deploy Schema
    /// Changes → Production, then flip this. Setting it back to `false` is the escape hatch.
    static let statementPaymentFieldsDeployed = false
}
