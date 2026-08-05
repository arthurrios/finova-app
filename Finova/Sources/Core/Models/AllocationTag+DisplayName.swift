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
/// happens to be cached, or replaced by one the user typed by hand.
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
    ///   - cache: the display-name store. Anything other than the shared instance bypasses the memo,
    ///     so tests stay hermetic.
    ///   - isEnabled: the user's preference. When off, machine translations are ignored - but see the
    ///     override tier below, which is not a machine translation.
    func displayName(
        in language: Locale.Language,
        cache: TagTranslationCache = .shared,
        isEnabled: Bool = UserDefaultsManager.isTagNameTranslationEnabled()
    ) -> String {
        guard cache === TagTranslationCache.shared else {
            return Self.resolveDisplayName(
                id: id, name: name, in: language, cache: cache, isEnabled: isEnabled)
        }
        return TagDisplayNameResolver.shared.displayName(
            id: id, name: name, in: language, cache: cache, isEnabled: isEnabled)
    }

    /// Whether this tag still needs translating for a given language. Used by the translation pass to
    /// build its work list; UI never asks.
    ///
    /// **Evaluates the machine chain only** - an override is invisible here on purpose. Defining this
    /// as `displayName == name` would make an overridden tag report "nothing to do", which is the
    /// right outcome for the wrong reason: it would bury the decision inside a display helper.
    /// Skipping overridden tags is the pass's call, and the pass makes it explicitly.
    func needsTranslation(
        for language: Locale.Language,
        cache: TagTranslationCache = .shared
    ) -> Bool {
        // Authored in the phone's language already - there is nothing to translate between a language
        // and itself, and the framework rejects such a pair anyway.
        if let source = cache.sourceLanguage(forTagId: id, name: name),
            Locale.Language(identifier: source).languageCode == language.languageCode {
            return false
        }
        return Self.cachedTranslation(id: id, name: name, in: language, cache: cache) == nil
    }

    // MARK: - The tiers

    /// The full walk, memo aside. Static so the resolver can run it without an `AllocationTag` in hand.
    fileprivate static func resolveDisplayName(
        id: String, name: String, in language: Locale.Language,
        cache: TagTranslationCache, isEnabled: Bool
    ) -> String {
        // 0. A name the user typed by hand, which outranks everything - including the preference.
        //
        //    Above `isEnabled` deliberately. The switch means "don't let a machine rename my tags"; it
        //    should not also discard something the user wrote. Turning translation off to escape one
        //    bad translation, and losing the correction you typed for it, would be a strange trade.
        if let override = lookup(in: language, exact: { cache.override(forTagId: id, language: $0) }) {
            return override
        }

        guard isEnabled else { return name }
        return machineDisplayName(id: id, name: name, in: language, cache: cache)
    }

    private static func machineDisplayName(
        id: String, name: String, in language: Locale.Language, cache: TagTranslationCache
    ) -> String {
        // 1. Authored in the phone's language already: the typed text IS the right answer, and a stale
        //    cache entry from a previous language must not override it.
        if let source = cache.sourceLanguage(forTagId: id, name: name),
            Locale.Language(identifier: source).languageCode == language.languageCode {
            return name
        }
        // 2. A cached machine translation, or failing that the authored name - never a placeholder,
        //    never a spinner.
        return cachedTranslation(id: id, name: name, in: language, cache: cache) ?? name
    }

    fileprivate static func cachedTranslation(
        id: String, name: String, in language: Locale.Language, cache: TagTranslationCache
    ) -> String? {
        lookup(in: language, exact: { cache.translation(forTagId: id, name: name, language: $0) })
    }

    /// Exact region first, then the bare language code.
    ///
    /// Apple treats pt-BR and pt-PT as different targets and pt-BR is one of the two locales this app
    /// ships, so an exact hit is worth preferring - but a cached "pt" is still a reasonable answer for
    /// a pt-PT phone, and better than falling all the way back to the typed name.
    private static func lookup(
        in language: Locale.Language, exact: (String) -> String?
    ) -> String? {
        let minimal = language.minimalIdentifier
        if let hit = exact(minimal) { return hit }
        guard let code = language.languageCode?.identifier, code != minimal else { return nil }
        return exact(code)
    }
}

// MARK: - Memo

/// Caches the resolved name so a layout pass does not re-walk the tiers for every cell.
///
/// The walk is cheap on its own, but it runs per tag list cell, per dashboard chip, three times per
/// chip for the accessibility label, and per donut arc - and each tier constructs a `Locale.Language`,
/// which is not free. A carousel rebuild ran it well over a hundred times.
///
/// **Invalidation is structural, not remembered.** The memo holds the cache generation, the target
/// language and the preference it was built under, and discards the whole map when any of them
/// differs. That is one integer compare on the hot path, and there is no per-key rule for a future
/// caller to forget: anything that mutates the cache bumps the generation, so anything that could
/// change an answer already invalidates it.
final class TagDisplayNameResolver {

    static let shared = TagDisplayNameResolver()

    private let lock = NSLock()
    private var memo: [String: String] = [:]
    private var generation: UInt64 = .max
    private var language = ""
    private var isEnabled = false

    func displayName(
        id: String, name: String, in language: Locale.Language,
        cache: TagTranslationCache, isEnabled: Bool
    ) -> String {
        let languageID = language.minimalIdentifier
        // Read before taking our own lock: this takes the cache's lock, and consistently acquiring
        // one before the other is what keeps the two from ever deadlocking.
        let generation = cache.generation
        let key = "\(id)|\(name)"

        lock.lock()
        if generation != self.generation || languageID != self.language || isEnabled != self.isEnabled {
            memo.removeAll(keepingCapacity: true)
            self.generation = generation
            self.language = languageID
            self.isEnabled = isEnabled
        } else if let hit = memo[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        // Resolved outside the lock, for the same ordering reason. Two threads resolving the same tag
        // just do the work twice and write the same answer.
        let resolved = AllocationTag.resolveDisplayName(
            id: id, name: name, in: language, cache: cache, isEnabled: isEnabled)

        lock.lock()
        // Keep it only if nothing moved underneath us while we were resolving.
        if generation == self.generation, languageID == self.language, isEnabled == self.isEnabled {
            memo[key] = resolved
        }
        lock.unlock()
        return resolved
    }
}
