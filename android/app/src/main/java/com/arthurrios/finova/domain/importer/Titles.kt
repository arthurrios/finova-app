package com.arthurrios.finova.domain.importer

import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionType
import java.text.Normalizer
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import kotlin.math.abs

/** A bank description turned into a title, with everything stripped kept on the side. */
data class CleanedTitle(
    val title: String,
    val raw: String,
    /** "PIX", "TED", "Débito automático": a category signal, but a poor title. */
    val railHint: String? = null,
    /** A `3/12` marker. Shown in the review, NOT acted on: real installments would hand inferred data to the series rules. */
    val installmentHint: Pair<Int, Int>? = null,
    /** A trailing document or authorisation number, kept so a row can be traced to the statement. */
    val strippedDocId: String? = null,
)

/** Bank description lines into something a person would recognise. Port of TitleCleaner.swift. */
object TitleCleaner {
    const val MAX_LENGTH = 120

    /** Longest first, so "Transferência enviada pelo Pix" beats "Transferência". Folded matching. */
    private val RailPrefixes = listOf(
        "transferencia enviada pelo pix" to "PIX",
        "transferencia recebida pelo pix" to "PIX",
        "transferencia enviada" to "Transferência",
        "transferencia recebida" to "Transferência",
        "pagamento de boleto" to "Boleto",
        "compra com cartao de credito" to "Crédito",
        "compra com cartao de debito" to "Débito",
        "compra no debito" to "Débito",
        "compra no credito" to "Crédito",
        "debito automatico" to "Débito automático",
        "pagamento efetuado" to "Pagamento",
        "pix qrs" to "PIX",
        "pix trf" to "PIX",
        "pix enviado" to "PIX",
        "pix recebido" to "PIX",
        "saque" to "Saque",
        "pagamento" to "Pagamento",
        "boleto" to "Boleto",
        "ted" to "TED",
        "doc" to "DOC",
        "pix" to "PIX",
    )

    /** Tokens that must survive re-casing intact. */
    private val PreservedTokens = setOf(
        "PIX", "TED", "DOC", "CNPJ", "CPF", "S/A", "SA", "LTDA", "ME", "EPP", "IOF", "IPTU",
        "IPVA", "DARF", "FGTS", "INSS", "CEF", "BB", "ATM", "POS", "QR", "US", "UK", "TV", "CD",
    )

    /** Connectors left dangling once a rail is removed: "PAGAMENTO DE SALARIO" becomes "Salario". */
    private val DanglingConnectors = listOf("de ", "da ", "do ", "para ", "pelo ", "pela ", "em ")

    /** @param untitled the last-resort title: `title` is required and is the main dedupe key. */
    fun clean(raw: String, untitled: String = "Untitled transaction"): CleanedTitle {
        // NFC first: macOS writes NFD, and the same merchant from two files must dedupe against itself.
        var text = Normalizer.normalize(raw, Normalizer.Form.NFC).replace(Whitespace, " ").trim()
        val original = text
        if (text.isEmpty()) return CleanedTitle("", raw)

        // A leading date echo: Itaú repeats the day inside the description.
        text = text.replace(LeadingDayMonth, "")
        val installment = InstallmentHint.find(text)?.let { match ->
            val index = match.groupValues[1].toInt()
            val total = match.groupValues[2].toInt()
            if (total > 1 && index in 1..total) {
                text = text.removeRange(match.range)
                index to total
            } else {
                null
            }
        }
        var docId: String? = null
        for (pattern in DocumentIds) {
            val match = pattern.find(text) ?: continue
            docId = match.groupValues[1]
            text = text.removeRange(match.range)
            break
        }
        val rail = extractRail(text)?.also { text = it.second }?.first

        text = text.trim { it in " -–—·•:,;/" }
        text = recase(text)
        if (text.length > MAX_LENGTH) text = text.take(MAX_LENGTH).trim()
        if (text.isEmpty()) text = rail ?: docId ?: original
        if (text.isEmpty()) text = untitled
        return CleanedTitle(text, raw, rail, installment, docId)
    }

    private val Whitespace = Regex("\\s+")
    private val LeadingDayMonth = Regex("""^\d{2}/\d{2}\s+""")
    private val InstallmentHint = Regex("""\s+(\d{1,2})\s*/\s*(\d{1,2})\s*$""")
    private val DocumentIds = listOf(
        Regex("""\s+(?:AUT|DOC|NSU|REF)\s*[:.]?\s*(\w{4,})\s*$""", RegexOption.IGNORE_CASE),
        Regex("""\s+(\d{6,})\s*$"""),
    )

    /** The rail label and what is left of the text, or null with no rail prefix. */
    private fun extractRail(text: String): Pair<String, String>? {
        val folded = text.normalizedForSearch()
        val (pattern, label) = RailPrefixes.firstOrNull { folded.startsWith(it.first) } ?: return null
        // Folding is 1:1 for the Latin script these prefixes use, so the offsets line up.
        var rest = text.drop(pattern.length).trim { it in " -–—:·•" }
        val remainder = rest.normalizedForSearch()
        DanglingConnectors.firstOrNull { remainder.startsWith(it) }?.let { connector ->
            // Only when something survives: "Pagamento de" alone keeps its word.
            val stripped = rest.drop(connector.length).trim()
            if (stripped.isNotEmpty()) rest = stripped
        }
        return label to rest
    }

    /**
     * Re-cases only text that is essentially all caps, holding acronyms back: blanket capitalizing
     * turns "PIX" into "Pix" and "S/A" into "S/a".
     */
    fun recase(text: String): String {
        val letters = text.filter { it.isLetter() }
        if (letters.isEmpty()) return text
        if (letters.count { it.isUpperCase() }.toDouble() / letters.length < 0.9) return text
        return text.split(' ').joinToString(" ") { word ->
            when {
                word.uppercase() in PreservedTokens -> word.uppercase()
                word.length <= 2 && word.any { it.isLetter() } -> word.uppercase()
                word.none { it.isLetter() } -> word
                else -> capitalizeFirstLetter(word)
            }
        }
    }

    /** Not a per-punctuation capitalize, which turns "NETFLIX.COM" into "Netflix.Com". */
    private fun capitalizeFirstLetter(word: String): String {
        val lowered = word.lowercase()
        val first = lowered.indexOfFirst { it.isLetter() }
        if (first < 0) return lowered
        return lowered.substring(0, first) + lowered[first].uppercaseChar() + lowered.substring(first + 1)
    }
}

/**
 * How alike two merchant strings are. Port of TitleSimilarity.swift: three cheap measures, maxed.
 */
object TitleSimilarity {
    /** Above this, two titles are the same merchant. */
    const val THRESHOLD = 0.60

    /** Tokens worth comparing: short words and bare numbers carry no identity. */
    fun tokens(title: String): Set<String> =
        title.normalizedForSearch().split(NonWord).filter { it.length > 2 && !it.all { c -> c.isDigit() } }.toSet()

    private val NonWord = Regex("[^\\p{L}\\p{N}]+")

    fun score(a: String, b: String) = score(tokens(a), tokens(b), a, b)

    fun score(a: Set<String>, b: Set<String>, rawA: String, rawB: String): Double {
        // Too few tokens for set measures: trigrams still tell "Netflix" from "Uber".
        if (a.isEmpty() || b.isEmpty()) return trigramDice(rawA.normalizedForSearch(), rawB.normalizedForSearch())
        val intersection = a.intersect(b).size.toDouble()
        val jaccard = intersection / a.union(b).size
        // "Netflix" against "NETFLIX.COM" is the most common real duplicate; containment gives it 1.0.
        // Gated, or a one-token title would sit inside every ride and meal.
        val containment = intersection / minOf(a.size, b.size)
        val usableContainment = if (containment >= 0.8) containment else 0.0
        // Trigrams see inside words: "PADARIA CENTRAL" against "PADARIA CENTRO" scores about 0.85.
        val trigram = trigramDice(rawA.normalizedForSearch(), rawB.normalizedForSearch())
        return maxOf(jaccard, usableContainment, trigram)
    }

    fun trigramDice(a: String, b: String): Double {
        val first = trigrams(a)
        val second = trigrams(b)
        if (first.isEmpty() || second.isEmpty()) return if (a == b) 1.0 else 0.0
        return 2.0 * first.intersect(second).size / (first.size + second.size)
    }

    private fun trigrams(text: String): Set<String> {
        val padded = "  $text "
        if (padded.length < 3) return emptySet()
        return (0..padded.length - 3).map { padded.substring(it, it + 3) }.toSet()
    }
}

/**
 * Matching imported rows against the ledger. Port of DuplicateIndex.swift. The key carries the SIGNED
 * amount: without the sign a refund matches the charge it refunds, and one of the two vanishes.
 */
class DuplicateIndex(existing: List<Transaction>) {
    data class Key(val day: LocalDate, val signedCents: Long, val normalizedTitle: String)

    private class Candidate(val id: Long, val day: LocalDate, val title: String, val tokens: Set<String>)

    private val exact = HashMap<Key, Long>()
    private val byAmount = HashMap<Long, MutableList<Candidate>>()

    init {
        for (transaction in existing) {
            val signed = signedCents(transaction.amount, transaction.type)
            exact[Key(transaction.date, signed, transaction.title.normalizedForSearch())] = transaction.id
            byAmount.getOrPut(signed) { mutableListOf() }
                .add(Candidate(transaction.id, transaction.date, transaction.title, TitleSimilarity.tokens(transaction.title)))
        }
    }

    fun exactMatch(key: Key): Long? = exact[key]

    /**
     * The same amount to the cent, within [FUZZY_DAY_WINDOW] days, and a similar title. The amount
     * stays EXACT: loosening it as well turns month-to-month recurring rows into matches.
     */
    fun fuzzyMatch(day: LocalDate, signedCents: Long, title: String): Pair<Long, Double>? {
        val bucket = byAmount[signedCents] ?: return null
        val tokens = TitleSimilarity.tokens(title)
        var best: Pair<Long, Double>? = null
        for (candidate in bucket) {
            if (abs(ChronoUnit.DAYS.between(candidate.day, day)) > FUZZY_DAY_WINDOW) continue
            val similarity = TitleSimilarity.score(tokens, candidate.tokens, title, candidate.title)
            if (similarity < TitleSimilarity.THRESHOLD) continue
            if (best == null || similarity > best.second) best = candidate.id to similarity
        }
        return best
    }

    companion object {
        /** Three days: a purchase posting on the Monday after a weekend. Wider starts matching different rows. */
        const val FUZZY_DAY_WINDOW = 3L

        fun signedCents(amount: Long, type: TransactionType) = if (type == TransactionType.Income) abs(amount) else -abs(amount)
    }
}
