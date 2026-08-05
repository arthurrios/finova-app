//
//  AllocationTag+DisplayName.swift
//  Finova
//

import Foundation

/// What a tag is called on screen, as opposed to what the user typed.
///
/// Mirrors the split `TransactionCategory` already uses: `key` is the stable stored value, `displayName`
/// is the presentation one. Here `name` is the stored value - authored by the user, never overwritten
/// by a machine - and `displayName` is it, translated into the phone's language when a translation
/// happens to be cached.
///
/// Resolution is a plain synchronous read. Nothing here waits on, or triggers, a translation: a view
/// that asked for one mid-layout would need an async state machine, and `MonthCarouselCell` rebuilds
/// on `.allocationTagsChanged`, so a render that caused a write would loop. Translations are produced
/// by a lifecycle pass and simply found here once they exist.
extension AllocationTag {

    /// The name to show, in the phone's current language.
    var displayName: String {
        displayName(in: Locale.current.language)
    }

    /// - Parameters:
    ///   - language: the target. Injected rather than read from `Locale` so tests do not depend on the
    ///     simulator's region.
    ///   - cache: the translation store.
    ///   - isEnabled: the user's preference. When off, the authored name is always used.
    func displayName(
        in language: Locale.Language,
        cache: TagTranslationCache = .shared,
        isEnabled: Bool = UserDefaultsManager.isTagNameTranslationEnabled()
    ) -> String {
        guard isEnabled else { return name }

        let targetCode = language.languageCode?.identifier

        // Authored in the phone's language already: the typed text IS the right answer, and a stale
        // cache entry from a previous language must not override it.
        if let source = cache.sourceLanguage(forTagId: id, name: name),
            Locale.Language(identifier: source).languageCode?.identifier == targetCode {
            return name
        }

        // Exact region first: Apple treats pt-BR and pt-PT as different targets, and pt-BR is one of
        // the two locales this app ships.
        if let hit = cache.translation(
            forTagId: id, name: name, language: language.minimalIdentifier) {
            return hit
        }

        // Same language, different region - a cached "pt" is a reasonable answer for a pt-PT phone.
        if let targetCode,
            let hit = cache.translation(forTagId: id, name: name, language: targetCode) {
            return hit
        }

        // Nothing usable. The authored name - never a placeholder, never a spinner.
        return name
    }

    /// Whether this tag still needs translating for a given language. Used by the translation pass to
    /// build its work list; UI never asks.
    func needsTranslation(
        for language: Locale.Language,
        cache: TagTranslationCache = .shared
    ) -> Bool {
        displayName(in: language, cache: cache, isEnabled: true) == name
            && cache.sourceLanguage(forTagId: id, name: name)
                .map { Locale.Language(identifier: $0).languageCode != language.languageCode }
                ?? true
    }
}
