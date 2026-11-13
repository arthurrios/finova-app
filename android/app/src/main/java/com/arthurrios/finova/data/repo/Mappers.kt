package com.arthurrios.finova.data.repo

import com.arthurrios.finova.data.db.BudgetEntity
import com.arthurrios.finova.data.db.TransactionEntity
import com.arthurrios.finova.domain.model.Budget
import com.arthurrios.finova.domain.model.BusinessDayRule
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType

fun TransactionEntity.toDomain() = Transaction(
    id = id,
    title = title,
    category = TransactionCategory.fromKey(category),
    type = TransactionType.fromKey(type),
    amount = amount,
    date = date,
    budgetMonth = budgetMonth,
    isRecurring = isRecurring,
    hasInstallments = hasInstallments,
    parentTransactionId = parentTransactionId,
    installmentNumber = installmentNumber,
    totalInstallments = totalInstallments,
    originalAmount = originalAmount,
    creditCardId = creditCardId,
    statementId = statementId,
    businessDayRule = BusinessDayRule.fromKey(businessDayRule),
    unadjustedDate = unadjustedDate,
    seriesPeriod = seriesPeriod,
    isStatementOverridden = isStatementOverridden,
    settledByTransactionId = settledByTransactionId,
    isEarlyPayment = isEarlyPayment,
    cancelledByTransactionId = cancelledByTransactionId,
    isCancellationRefund = isCancellationRefund,
    statementPaymentId = statementPaymentId,
    isStatementPayment = isStatementPayment,
)

fun Transaction.toEntity() = TransactionEntity(
    id = id,
    title = title,
    category = category.key,
    type = type.key,
    amount = amount,
    date = date,
    budgetMonth = budgetMonth,
    isRecurring = isRecurring,
    hasInstallments = hasInstallments,
    parentTransactionId = parentTransactionId,
    installmentNumber = installmentNumber,
    totalInstallments = totalInstallments,
    originalAmount = originalAmount,
    creditCardId = creditCardId,
    statementId = statementId,
    isStatementOverridden = isStatementOverridden,
    settledByTransactionId = settledByTransactionId,
    isEarlyPayment = isEarlyPayment,
    cancelledByTransactionId = cancelledByTransactionId,
    isCancellationRefund = isCancellationRefund,
    statementPaymentId = statementPaymentId,
    isStatementPayment = isStatementPayment,
    businessDayRule = businessDayRule.key,
    // iOS writers always set these; readers treat null as "same as date / budget month".
    unadjustedDate = unadjustedDate ?: date,
    seriesPeriod = seriesPeriod ?: budgetMonth,
)

fun BudgetEntity.toDomain() = Budget(month, amount)
fun Budget.toEntity() = BudgetEntity(month, amount)
