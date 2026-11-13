package com.arthurrios.finova.domain.importer

import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType
import java.util.Locale

/** Where a suggestion came from. Shown on the review screen. */
enum class CategorySource { History, Rules, BankColumn, Rail, Fallback }

data class CategorySuggestion(val category: TransactionCategory, val source: CategorySource, val confidence: Double)

/** One keyword rule. Port of MerchantRule.swift. */
data class MerchantRule(
    val id: String,
    /** Already accent-folded and lowercase. */
    val patterns: List<String>,
    val match: Match,
    /** A [TransactionCategory.key]. */
    val category: String,
    /** "income" or "expense": "pagamento" means different things on each side. */
    val typeConstraint: String?,
    val priority: Int,
) {
    enum class Match { Contains, Prefix, WholeWord }

    fun matches(normalizedTitle: String, type: TransactionType): Boolean {
        if (typeConstraint != null && typeConstraint != type.key) return false
        return patterns.any { pattern ->
            when (match) {
                Match.Contains -> normalizedTitle.contains(pattern)
                Match.Prefix -> normalizedTitle.startsWith(pattern)
                Match.WholeWord -> normalizedTitle.split(NonWord).any { it == pattern }
            }
        }
    }

    /** The longest pattern, to prefer the most specific rule. */
    val specificity: Int get() = patterns.maxOfOrNull { it.length } ?: 0

    private companion object {
        val NonWord = Regex("[^\\p{L}\\p{N}]+")
    }
}

/**
 * The rules for this phone. The Brazilian set joins by REGION, not app language: someone running the
 * app in English while living in Brazil still has Portuguese merchants on their statement.
 */
class MerchantRuleSet(region: String? = Locale.getDefault().country) {
    private val rules: List<MerchantRule> =
        (MerchantRuleData.Base + if (region == "BR") MerchantRuleData.PtBR else emptyList())
            // Most specific first, then priority, so the first match is the best one.
            .sortedWith(compareByDescending<MerchantRule> { it.specificity }.thenByDescending { it.priority })

    fun category(normalizedTitle: String, type: TransactionType): TransactionCategory? {
        for (rule in rules) {
            if (!rule.matches(normalizedTitle, type)) continue
            TransactionCategory.entries.firstOrNull { it.key == rule.category }?.let { return it }
        }
        return null
    }
}

/** Normalized title to the category this user actually uses for it. Port of HistoricalCategoryIndex. */
class HistoricalCategoryIndex(existing: List<Transaction>) {
    private val byExactTitle = HashMap<String, TransactionCategory>()
    private val byToken = HashMap<String, MutableMap<TransactionCategory, Int>>()

    init {
        val counts = HashMap<String, MutableMap<TransactionCategory, Int>>()
        for (transaction in existing) {
            val key = transaction.title.normalizedForSearch()
            if (key.isEmpty()) continue
            counts.getOrPut(key) { mutableMapOf() }.merge(transaction.category, 1, Int::plus)
            for (token in tokens(key)) byToken.getOrPut(token) { mutableMapOf() }.merge(transaction.category, 1, Int::plus)
        }
        for ((title, histogram) in counts) {
            val (category, count) = histogram.maxBy { it.value }.toPair()
            // Twice, or once with a category the user chose: a lone `miscellaneous` is nobody's choice.
            if (count >= 2 || category != TransactionCategory.Miscellaneous) byExactTitle[title] = category
        }
    }

    fun lookup(normalizedTitle: String): CategorySuggestion? {
        byExactTitle[normalizedTitle]?.let { return CategorySuggestion(it, CategorySource.History, 0.95) }
        // Token fallback: "PADARIA CENTRAL LTDA" against a remembered "PADARIA CENTRAL".
        val votes = mutableMapOf<TransactionCategory, Int>()
        for (token in tokens(normalizedTitle)) byToken[token]?.forEach { (category, count) -> votes.merge(category, count, Int::plus) }
        val best = votes.maxByOrNull { it.value } ?: return null
        return if (best.value >= 2) CategorySuggestion(best.key, CategorySource.History, 0.7) else null
    }

    private fun tokens(normalized: String) =
        normalized.split(NonWord).filter { it.length > 3 && !it.all { c -> c.isDigit() } }

    private companion object {
        val NonWord = Regex("[^\\p{L}\\p{N}]+")
    }
}

/**
 * Suggestions that always exist, work offline, and never change between runs. Port of
 * DeterministicCategorizer.swift. The user's OWN history comes first: only it can tell that
 * "PAG*JOSESILVA" is the gym. (iOS 26 can also ask Apple's on-device model to refine weak guesses;
 * Android has no equivalent, so it stops here.)
 *
 * @param categoryNames each category's name in the app language, to match the bank's own category column.
 */
class DeterministicCategorizer(
    existing: List<Transaction>,
    private val rules: MerchantRuleSet = MerchantRuleSet(),
    private val categoryNames: Map<TransactionCategory, String> = emptyMap(),
) {
    private val history = HistoricalCategoryIndex(existing)

    fun categorize(title: CleanedTitle, type: TransactionType, bankCategory: String? = null): CategorySuggestion {
        val normalized = title.title.normalizedForSearch()
        history.lookup(normalized)?.let { return it }

        if (bankCategory != null) {
            val folded = bankCategory.normalizedForSearch()
            TransactionCategory.entries.firstOrNull {
                it.key.normalizedForSearch() == folded || categoryNames[it]?.normalizedForSearch() == folded
            }?.let { return CategorySuggestion(it, CategorySource.BankColumn, 0.8) }
        }

        rules.category(normalized, type)?.let { return CategorySuggestion(it, CategorySource.Rules, 0.75) }
        railCategory(title, normalized, type)?.let { return it }
        return CategorySuggestion(TransactionCategory.Miscellaneous, CategorySource.Fallback, 0.2)
    }

    private fun railCategory(title: CleanedTitle, normalized: String, type: TransactionType): CategorySuggestion? {
        if (type == TransactionType.Income && (normalized.contains("salario") || normalized.contains("salary"))) {
            return CategorySuggestion(TransactionCategory.Salary, CategorySource.Rail, 0.5)
        }
        if (normalized.contains("fatura") || normalized.contains("cartao de credito")) {
            return CategorySuggestion(TransactionCategory.CreditCard, CategorySource.Rail, 0.5)
        }
        return when (title.railHint) {
            "PIX", "TED", "DOC", "Transferência" -> CategorySuggestion(TransactionCategory.Transfer, CategorySource.Rail, 0.4)
            "Boleto" -> CategorySuggestion(TransactionCategory.BankSlip, CategorySource.Rail, 0.4)
            "Saque" -> CategorySuggestion(TransactionCategory.Miscellaneous, CategorySource.Rail, 0.3)
            else -> null
        }
    }
}
