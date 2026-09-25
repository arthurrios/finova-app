package com.arthurrios.finova.domain.model

/** Stored as the lowercase key, like iOS (`"income"` / `"expense"`). */
enum class TransactionType(val key: String) {
    Income("income"),
    Expense("expense");

    companion object {
        /** Unknown or empty values read as expense, as on iOS. */
        fun fromKey(key: String?): TransactionType = entries.firstOrNull { it.key.equals(key, ignoreCase = true) } ?: Expense
    }
}

/** How a date that lands on a weekend moves. Port of BusinessDayRule.swift. */
enum class BusinessDayRule(val key: String) {
    Exact("exact"),
    NextBusinessDay("nextBusinessDay"),
    PreviousBusinessDay("previousBusinessDay");

    companion object {
        /** Null or unknown reads as exact (`BusinessDayRule.fromStored`). */
        fun fromKey(key: String?): BusinessDayRule = entries.firstOrNull { it.key == key } ?: Exact
    }
}

/**
 * The 27 categories, in the iOS order. [key] is what the database stores (the Swift case name).
 * Port of TransactionCategory in TransactionModel.swift.
 */
enum class TransactionCategory(val key: String) {
    Market("market"),
    Meals("meals"),
    Gifts("gifts"),
    Salary("salary"),
    Utilities("utilities"),
    Entertainment("entertainment"),
    Transportation("transportation"),
    Healthcare("healthcare"),
    Subscriptions("subscriptions"),
    Education("education"),
    Travel("travel"),
    Groceries("groceries"),
    Insurance("insurance"),
    Savings("savings"),
    Investments("investments"),
    Taxes("taxes"),
    Loans("loans"),
    Donations("donations"),
    Miscellaneous("miscellaneous"),
    Clothing("clothing"),
    PersonalCare("personalCare"),
    HomeMaintenance("homeMaintenance"),
    Communication("communication"),
    Fitness("fitness"),
    Transfer("transfer"),
    BankSlip("bankSlip"),
    CreditCard("creditCard");

    companion object {
        /**
         * Lenient read, same order as iOS: empty is miscellaneous; then the exact key; then the
         * "category.<key>" localization key; then a case-insensitive key; else miscellaneous.
         */
        fun fromKey(raw: String?): TransactionCategory {
            if (raw.isNullOrEmpty()) return Miscellaneous
            entries.firstOrNull { it.key == raw }?.let { return it }
            val stripped = raw.removePrefix("category.")
            entries.firstOrNull { it.key == stripped }?.let { return it }
            return entries.firstOrNull { it.key.equals(stripped, ignoreCase = true) } ?: Miscellaneous
        }
    }
}
