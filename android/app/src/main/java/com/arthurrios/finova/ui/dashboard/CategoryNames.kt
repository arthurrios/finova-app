package com.arthurrios.finova.ui.dashboard

import androidx.annotation.StringRes
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionCategory.*

/** The display name, from the iOS "category.<key>" strings. */
@get:StringRes
val TransactionCategory.label: Int
    get() = when (this) {
    Market -> R.string.category_market
    Meals -> R.string.category_meals
    Gifts -> R.string.category_gifts
    Salary -> R.string.category_salary
    Utilities -> R.string.category_utilities
    Entertainment -> R.string.category_entertainment
    Transportation -> R.string.category_transportation
    Healthcare -> R.string.category_healthcare
    Subscriptions -> R.string.category_subscriptions
    Education -> R.string.category_education
    Travel -> R.string.category_travel
    Groceries -> R.string.category_groceries
    Insurance -> R.string.category_insurance
    Savings -> R.string.category_savings
    Investments -> R.string.category_investments
    Taxes -> R.string.category_taxes
    Loans -> R.string.category_loans
    Donations -> R.string.category_donations
    Miscellaneous -> R.string.category_miscellaneous
    Clothing -> R.string.category_clothing
    PersonalCare -> R.string.category_personal_care
    HomeMaintenance -> R.string.category_home_maintenance
    Communication -> R.string.category_communication
    Fitness -> R.string.category_fitness
    Transfer -> R.string.category_transfer
    BankSlip -> R.string.category_bank_slip
    CreditCard -> R.string.category_credit_card
    }
