//
//  TagTranslationCache.swift
//  Finova
//

import Foundation

/// Display names for allocation tags — machine translations, the source language each name was typed
/// in, and any name the user has typed by hand to replace a translation. Stored per device.
///
/// **Deliberately not part of `AllocationTagBook`.** The book syncs as one blob resolved
/// last-writer-wins on `updatedAt` (see `AllocationTagBookSync`), so anything written into it claims
/// authorship of the whole book. A background translation pass writing there would stamp a new
/// `updatedAt` and push - and a peer that had added a tag while offline would lose it to the race.
/// Turning a cosmetic background task into a data-loss amplifier is not a trade worth making for a
/// cache that can be regenerated for free.
///
/// Keeping it device-local also happens to be more correct: the target language is a property of the
/// phone, not of the account. Two devices in two languages each want their own answer, and each can
/// produce it on-device in milliseconds.
///
/// **Overrides are the one entry that is not regenerable**, since the user typed them. They are still
/// device-local, for two reasons: they are scoped to a target language, which is a property of the
/// phone; and an override is a repair for a bad machine translation, which depends on the model
/// version that device happens to have. The migration is one-way safe if that changes — a local
/// override can seed a synced field later, where a synced field cannot be un-synced without a story
/// for the peers that already have it.
/// TODO: revisit syncing overrides via `AllocationTag.nameOverrides` + `schemaVersion` 2.
///
/// Reads are served from memory and are on the layout path (`AllocationTag.displayName` runs per cell,
/// per chip and per donut arc), so the plist is deserialised once per uid rather than once per call.
/// The lock is what makes the read-modify-write in each setter atomic: this is reached from the
/// `@MainActor` coordinator *and* from the non-isolated `AllocationTagService`, and before it two
/// concurrent writes could silently drop one.
final class TagTranslationCache {

    static let shared = TagTranslationCache()

    private let defaults: UserDefaults
    private let uidProvider: () -> String?

    private let lock = NSLock()
    private var translations: [String: String] = [:]
    private var sources: [String: String] = [:]
    private var overrides: [String: String] = [:]
    private var loadedUid: String?
    private var isLoaded = false
    private var _generation: UInt64 = 0

    init(
        defaults: UserDefaults = .standard,
        uidProvider: @escaping () -> String? = { UIDUserDefaultsManager.shared.currentUserUID }
    ) {
        self.defaults = defaults
        self.uidProvider = uidProvider
    }

    // MARK: - Keys

    private static let storeKeyPrefix = "allocationTagTranslations_v1_"
    private static let sourceKeyPrefix = "allocationTagSourceLanguages_v1_"
    private static let overrideKeyPrefix = "allocationTagNameOverrides_v1_"

    /// The tag's *name* is part of the key, so renaming a tag misses the cache automatically and no
    /// separate invalidation is needed. A stale entry for the old name is inert and costs a few bytes.
    private func entryKey(tagId: String, name: String, language: String) -> String {
        "\(tagId)|\(name)|\(language)"
    }

    private func sourceKey(tagId: String, name: String) -> String {
        "\(tagId)|\(name)"
    }

    /// Note the absence of the name — see `setOverride`.
    private func overrideKey(tagId: String, language: String) -> String {
        "\(tagId)|\(language)"
    }

    // MARK: - Loading

    /// Bumped on every mutation, and whenever the signed-in user changes. `TagDisplayNameResolver`
    /// memoises resolved names against this, so invalidation is one integer compare rather than a set
    /// of per-key rules somebody has to remember to update.
    var generation: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        return _generation
    }

    /// Loads the maps for the current user if they are not already in hand. Call with the lock held.
    ///
    /// Returns whether there is a user to store anything against. Mutators must honour that and bail:
    /// with no uid there is nowhere to persist, and writing to the in-memory maps anyway would serve
    /// a phantom entry back on the next read and then lose it the moment somebody signs in.
    @discardableResult
    private func loadIfNeeded() -> Bool {
        let uid = uidProvider()
        if isLoaded, loadedUid == uid { return !(loadedUid ?? "").isEmpty }

        loadedUid = uid
        isLoaded = true
        _generation &+= 1

        // No signed-in user: every read misses and every write is dropped. Deliberate — these are
        // keyed per uid, and writing them unkeyed would leak one account's names into the next.
        guard let uid, !uid.isEmpty else {
            translations = [:]
            sources = [:]
            overrides = [:]
            return false
        }
        translations = (defaults.dictionary(forKey: Self.storeKeyPrefix + uid) as? [String: String]) ?? [:]
        sources = (defaults.dictionary(forKey: Self.sourceKeyPrefix + uid) as? [String: String]) ?? [:]
        overrides = (defaults.dictionary(forKey: Self.overrideKeyPrefix + uid) as? [String: String]) ?? [:]
        return true
    }

    /// Call with the lock held, after a `loadIfNeeded` that returned `true`.
    private func flush(_ map: [String: String], _ prefix: String) {
        guard let uid = loadedUid, !uid.isEmpty else { return }
        defaults.set(map, forKey: prefix + uid)
        _generation &+= 1
    }

    /// Drops the in-memory copy so the next read reloads. Wire this to sign-in and sign-out alongside
    /// `AllocationTagService.invalidateCache()`.
    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        isLoaded = false
        loadedUid = nil
        translations = [:]
        sources = [:]
        overrides = [:]
        _generation &+= 1
    }

    // MARK: - Translations

    func translation(forTagId tagId: String, name: String, language: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        return translations[entryKey(tagId: tagId, name: name, language: language)]
    }

    func store(_ translation: String, forTagId tagId: String, name: String, language: String) {
        let trimmed = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        // A translator that hands back its input has not translated anything; caching that would look
        // like a success and stop us ever trying again.
        guard !trimmed.isEmpty, trimmed != name else { return }

        lock.lock()
        defer { lock.unlock() }
        guard loadIfNeeded() else { return }

        // A machine translation never lands on top of a name the user typed. The pass already filters
        // overridden tags out of its work list, so reaching this is a bug — but the invariant belongs
        // here, where it survives a caller who forgets.
        guard !hasOverrideLocked(tagId: tagId, language: language) else { return }

        translations[entryKey(tagId: tagId, name: name, language: language)] = trimmed
        flush(translations, Self.storeKeyPrefix)
    }

    // MARK: - Source language

    /// The language a tag's name was typed in, as a `Locale.Language.minimalIdentifier`.
    func sourceLanguage(forTagId tagId: String, name: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        return sources[sourceKey(tagId: tagId, name: name)]
    }

    func storeSourceLanguage(_ language: String, forTagId tagId: String, name: String) {
        guard !language.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard loadIfNeeded() else { return }
        sources[sourceKey(tagId: tagId, name: name)] = language
        flush(sources, Self.sourceKeyPrefix)
    }

    // MARK: - User overrides

    /// A display name the user typed to replace a machine translation.
    func override(forTagId tagId: String, language: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        return overrides[overrideKey(tagId: tagId, language: language)]
    }

    /// `nil` or blank clears the override and hands the tag back to the translation pass.
    ///
    /// **Keyed without the name, so an override deliberately survives a rename.** The machine key
    /// includes the name because the name is the *input* to a translation — a new name is a different
    /// question and the old answer is meaningless. That reasoning does not carry: an override is not a
    /// function of the name, it is an independent string the user attached to the tag. The rename that
    /// most often follows an override is a correction of the authored name ("Essentials" →
    /// "Essential expenses"), and dropping what they typed to fix a bad translation at exactly the
    /// moment they are tidying the tag is the worst possible timing. The costs are asymmetric too:
    /// losing a machine translation is free, losing user-authored content is not. There is a visible
    /// escape hatch — the override lives in an editable field on the tag edit screen — which beats an
    /// implicit rule the user cannot see.
    ///
    /// An override equal to the tag's own name is legitimate and is NOT rejected: it is how the user
    /// says "leave this one alone" for a single tag without turning the whole feature off.
    func setOverride(_ text: String?, forTagId tagId: String, language: String) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        lock.lock()
        defer { lock.unlock() }
        guard loadIfNeeded() else { return }

        let key = overrideKey(tagId: tagId, language: language)
        if trimmed.isEmpty {
            guard overrides.removeValue(forKey: key) != nil else { return }
        } else {
            guard overrides[key] != trimmed else { return }
            overrides[key] = trimmed
        }
        flush(overrides, Self.overrideKeyPrefix)
    }

    /// Call with the lock held. Mirrors the exact-region-then-language-code walk `displayName` does,
    /// so an override typed on a pt-BR phone still shields the tag when the pass targets bare "pt".
    private func hasOverrideLocked(tagId: String, language: String) -> Bool {
        if overrides[overrideKey(tagId: tagId, language: language)] != nil { return true }
        guard let code = Locale.Language(identifier: language).languageCode?.identifier,
            code != language
        else { return false }
        return overrides[overrideKey(tagId: tagId, language: code)] != nil
    }

    // MARK: - Housekeeping

    /// Drops everything for a tag. Only needed on delete - a rename is handled by the translation and
    /// source keys including the name, and by an override being meant to survive one.
    ///
    /// Overrides are included: they outlive a rename by design, so without this a deleted tag's
    /// override would be inherited by any tag that reused the id.
    func forget(tagId: String) {
        lock.lock()
        defer { lock.unlock() }
        guard loadIfNeeded() else { return }

        let prefix = "\(tagId)|"
        translations = translations.filter { !$0.key.hasPrefix(prefix) }
        sources = sources.filter { !$0.key.hasPrefix(prefix) }
        overrides = overrides.filter { !$0.key.hasPrefix(prefix) }
        flush(translations, Self.storeKeyPrefix)
        flush(sources, Self.sourceKeyPrefix)
        flush(overrides, Self.overrideKeyPrefix)
    }

    func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()

        translations = [:]
        sources = [:]
        overrides = [:]
        guard let uid = loadedUid, !uid.isEmpty else { return }
        for prefix in [Self.storeKeyPrefix, Self.sourceKeyPrefix, Self.overrideKeyPrefix] {
            defaults.removeObject(forKey: prefix + uid)
        }
        _generation &+= 1
    }
}
