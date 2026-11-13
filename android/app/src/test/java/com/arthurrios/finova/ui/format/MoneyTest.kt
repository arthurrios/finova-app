package com.arthurrios.finova.ui.format

import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.Locale

class MoneyTest {
    @Test fun compactAmountsAlwaysUseAPoint() {
        val portuguese = Locale.forLanguageTag("pt-BR")
        assertEquals("R$28.3k", Money.compact(2_830_000, "BRL", portuguese))
        assertEquals("R$1.5M", Money.compact(150_000_000, "BRL", portuguese))
        assertEquals("R$250k", Money.compact(25_000_000, "BRL", portuguese))
    }

    @Test fun fullAmountsKeepThePhonesFormat() {
        assertEquals("R$ 28.300,00", Money.format(2_830_000, "BRL", Locale.forLanguageTag("pt-BR")).replace(' ', ' '))
    }
}
