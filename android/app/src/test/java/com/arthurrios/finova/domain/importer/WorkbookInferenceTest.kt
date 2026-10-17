package com.arthurrios.finova.domain.importer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A workbook's readers write numbers with a POSIX point (`1069.65`). Profiled as pt-BR, the dot reads
 * as thousands and the running balance never proves the amount column; profiled as en-US it does.
 */
class WorkbookInferenceTest {
    private val rows = listOf(
        SourceRow(1, listOf("Data", "Descrição", "Valor", "Saldo")),
        SourceRow(2, listOf("21/10/2026", "PIX RECEBIDO MARIA", "250", "1250")),
        SourceRow(3, listOf("22/10/2026", "MERCADO EXTRA", "-180.35", "1069.65")),
        SourceRow(4, listOf("24/10/2026", "DROGARIA SAO PAULO", "-42.1", "1027.55")),
        SourceRow(5, listOf("25/10/2026", "SALARIO", "3200", "4227.55")),
    )

    @Test fun workbookNumbersProveTheRunningBalance() {
        val result = SchemaInferencer.infer(rows, NumberFormatSpec.EnUS)!!
        assertEquals(SignConvention.NegativeIsExpense, result.schema.signConvention)
        assertEquals(1.0, result.confidence.signConvention.score, 0.0)
        assertEquals(ColumnRole.Amount, result.schema.roles[2])
        assertEquals(ColumnRole.Balance, result.schema.roles[3])
    }

    @Test fun readAsBrazilianNumbersTheSameRowsProveNothing() {
        val result = SchemaInferencer.infer(rows)!!
        assertTrue(result.confidence.signConvention.score < 0.6)
    }
}
