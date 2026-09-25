package com.arthurrios.finova.ui.dashboard

import androidx.annotation.DrawableRes
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionCategory.*
import com.arthurrios.finova.domain.model.TransactionType

/**
 * Port of `TransactionCategory.iconName(for:)`: the Lucide icon named after the category, a
 * direction-aware icon for transfers, and the dollar icon when no icon exists (miscellaneous).
 */
@DrawableRes
fun TransactionCategory.icon(type: TransactionType): Int = when (this) {
    CreditCard -> R.drawable.ic_lucide_icon_credit_card
    Transfer -> if (type == TransactionType.Income) R.drawable.ic_lucide_icon_transfer_down else R.drawable.ic_lucide_icon_transfer_up
    Market -> R.drawable.ic_lucide_icon_market
    Meals -> R.drawable.ic_lucide_icon_meals
    Gifts -> R.drawable.ic_lucide_icon_gifts
    Salary -> R.drawable.ic_lucide_icon_salary
    Utilities -> R.drawable.ic_lucide_icon_utilities
    Entertainment -> R.drawable.ic_lucide_icon_entertainment
    Transportation -> R.drawable.ic_lucide_icon_transportation
    Healthcare -> R.drawable.ic_lucide_icon_healthcare
    Subscriptions -> R.drawable.ic_lucide_icon_subscriptions
    Education -> R.drawable.ic_lucide_icon_education
    Travel -> R.drawable.ic_lucide_icon_travel
    Groceries -> R.drawable.ic_lucide_icon_groceries
    Insurance -> R.drawable.ic_lucide_icon_insurance
    Savings -> R.drawable.ic_lucide_icon_savings
    Investments -> R.drawable.ic_lucide_icon_investments
    Taxes -> R.drawable.ic_lucide_icon_taxes
    Loans -> R.drawable.ic_lucide_icon_loans
    Donations -> R.drawable.ic_lucide_icon_donations
    Clothing -> R.drawable.ic_lucide_icon_clothing
    PersonalCare -> R.drawable.ic_lucide_icon_personal_care
    HomeMaintenance -> R.drawable.ic_lucide_icon_home_maintenance
    Communication -> R.drawable.ic_lucide_icon_communication
    Fitness -> R.drawable.ic_lucide_icon_fitness
    BankSlip -> R.drawable.ic_lucide_icon_bank_slip
    Miscellaneous -> R.drawable.ic_lucide_icon_dollar
}
