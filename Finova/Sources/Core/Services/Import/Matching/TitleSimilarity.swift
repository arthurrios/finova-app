//
//  TitleSimilarity.swift
//  Finova
//
//  How alike two merchant strings are.
//
//  Deliberately not `NLEmbedding` (per-word, patchy pt-BR coverage, and merchant strings are not
//  prose) and not raw Levenshtein (O(n·m) per pair, and it scores "PADARIA CENTRAL" against
//  "PADARIA CENTRO" no differently from noise). Three cheap set/string measures, maxed.
//

import Foundation

enum TitleSimilarity {

    /// Above this, two titles are treated as the same merchant.
    static let threshold = 0.60

    /// Tokens worth comparing: short words and bare numbers carry no identity.
    ///
    /// Written as statements rather than one chained expression — the fused
    /// `Set(split.map.filter)` form takes the type checker past its budget and fails to compile.
    static func tokens(of title: String) -> Set<String> {
        let normalized = title.normalizedForSearch()
        let pieces: [Substring] = normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        var result: Set<String> = []
        for piece in pieces where piece.count > 2 {
            if piece.allSatisfy(\.isNumber) { continue }
            result.insert(String(piece))
        }
        return result
    }

    static func score(_ a: String, _ b: String) -> Double {
        let tokensA = tokens(of: a)
        let tokensB = tokens(of: b)
        return score(tokensA, tokensB, rawA: a, rawB: b)
    }

    static func score(
        _ a: Set<String>, _ b: Set<String>, rawA: String, rawB: String
    ) -> Double {
        // Too few usable tokens on either side for set measures to mean anything — fall back to
        // character trigrams, which still separate "Netflix" from "Uber".
        guard !a.isEmpty, !b.isEmpty else {
            return trigramDice(rawA.normalizedForSearch(), rawB.normalizedForSearch())
        }

        let intersection = Double(a.intersection(b).count)
        let jaccard = intersection / Double(a.union(b).count)

        // Containment is NOT optional. "Netflix" against "NETFLIX.COM" gives a Jaccard of 0.5 —
        // BELOW threshold — and that pair is the single most common real duplicate: an imported row
        // against an existing recurring instance the user titled more briefly. Containment gives 1.0.
        let containment = intersection / Double(min(a.count, b.count))
        // Gated: a one-token title is inside almost anything, so unrestricted containment would
        // match "uber" to every ride, meal and subscription at once.
        let usableContainment = containment >= 0.8 ? containment : 0

        // Always consulted, not just for short titles. Token measures treat "PADARIA CENTRAL" and
        // "PADARIA CENTRO" as sharing one token out of three — 0.33, well under threshold — because
        // they cannot see inside a word. Character trigrams can, and score that pair around 0.85,
        // while still keeping "UBER TRIP" and "MERCADO EXTRA" far apart.
        let trigram = trigramDice(rawA.normalizedForSearch(), rawB.normalizedForSearch())

        return max(jaccard, max(usableContainment, trigram))
    }

    /// Dice coefficient over character trigrams.
    static func trigramDice(_ a: String, _ b: String) -> Double {
        let tri1 = trigrams(a)
        let tri2 = trigrams(b)
        guard !tri1.isEmpty, !tri2.isEmpty else { return a == b ? 1 : 0 }
        let shared = Double(tri1.intersection(tri2).count)
        return 2 * shared / Double(tri1.count + tri2.count)
    }

    private static func trigrams(_ text: String) -> Set<String> {
        let padded = Array("  \(text) ")
        guard padded.count >= 3 else { return [] }
        var result: Set<String> = []
        for i in 0...(padded.count - 3) {
            result.insert(String(padded[i..<(i + 3)]))
        }
        return result
    }
}
