//
//  TagTranslationCache.swift
//  Finova
//

import Foundation

/// Machine translations of allocation tag names, stored per device.
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
final class TagTranslationCache {

    static let shared = TagTranslationCache()

    private let defaults: UserDefaults
    private let uidProvider: () -> String?

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

    /// The tag's *name* is part of the key, so renaming a tag misses the cache automatically and no
    /// separate invalidation is needed. A stale entry for the old name is inert and costs a few bytes.
    private func entryKey(tagId: String, name: String, language: String) -> String {
        "\(tagId)|\(name)|\(language)"
    }

    private func sourceKey(tagId: String, name: String) -> String {
        "\(tagId)|\(name)"
    }

    private func storageKey(_ prefix: String) -> String? {
        guard let uid = uidProvider(), !uid.isEmpty else { return nil }
        return prefix + uid
    }

    // MARK: - Translations

    func translation(forTagId tagId: String, name: String, language: String) -> String? {
        guard let key = storageKey(Self.storeKeyPrefix),
            let map = defaults.dictionary(forKey: key) as? [String: String]
        else { return nil }
        return map[entryKey(tagId: tagId, name: name, language: language)]
    }

    func store(_ translation: String, forTagId tagId: String, name: String, language: String) {
        let trimmed = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        // A translator that hands back its input has not translated anything; caching that would look
        // like a success and stop us ever trying again.
        guard !trimmed.isEmpty, trimmed != name, let key = storageKey(Self.storeKeyPrefix) else {
            return
        }
        var map = (defaults.dictionary(forKey: key) as? [String: String]) ?? [:]
        map[entryKey(tagId: tagId, name: name, language: language)] = trimmed
        defaults.set(map, forKey: key)
    }

    // MARK: - Source language

    /// The language a tag's name was typed in, as a `Locale.Language.minimalIdentifier`.
    func sourceLanguage(forTagId tagId: String, name: String) -> String? {
        guard let key = storageKey(Self.sourceKeyPrefix),
            let map = defaults.dictionary(forKey: key) as? [String: String]
        else { return nil }
        return map[sourceKey(tagId: tagId, name: name)]
    }

    func storeSourceLanguage(_ language: String, forTagId tagId: String, name: String) {
        guard !language.isEmpty, let key = storageKey(Self.sourceKeyPrefix) else { return }
        var map = (defaults.dictionary(forKey: key) as? [String: String]) ?? [:]
        map[sourceKey(tagId: tagId, name: name)] = language
        defaults.set(map, forKey: key)
    }

    // MARK: - Housekeeping

    /// Drops everything for a tag. Only needed on delete - a rename is handled by the key including
    /// the name.
    func forget(tagId: String) {
        for prefix in [Self.storeKeyPrefix, Self.sourceKeyPrefix] {
            guard let key = storageKey(prefix),
                var map = defaults.dictionary(forKey: key) as? [String: String]
            else { continue }
            map = map.filter { !$0.key.hasPrefix("\(tagId)|") }
            defaults.set(map, forKey: key)
        }
    }

    func clearAll() {
        for prefix in [Self.storeKeyPrefix, Self.sourceKeyPrefix] {
            guard let key = storageKey(prefix) else { continue }
            defaults.removeObject(forKey: key)
        }
    }
}
