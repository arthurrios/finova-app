package com.arthurrios.finova.ui.cards

import androidx.annotation.StringRes
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.model.CardBrand
import com.arthurrios.finova.domain.model.CardColor

/** CardColor.startColor / endColor on iOS. */
val CardColor.start: Color
    get() = when (this) {
        CardColor.Black -> Color(0xFF000000)
        CardColor.Purple -> Color(0xFF8B5CF6)
        CardColor.Blue -> Color(0xFF3B82F6)
        CardColor.Green -> Color(0xFF10B981)
        CardColor.Gold -> Color(0xFFF59E0B)
        CardColor.Platinum -> Color(0xFF94A3B8)
        CardColor.Red -> Color(0xFFEF4444)
        CardColor.Orange -> Color(0xFFF97316)
    }

val CardColor.end: Color
    get() = when (this) {
        // UIColor.darkGray.
        CardColor.Black -> Color(0xFF555555)
        CardColor.Purple -> Color(0xFF6D28D9)
        CardColor.Blue -> Color(0xFF1D4ED8)
        CardColor.Green -> Color(0xFF059669)
        CardColor.Gold -> Color(0xFFD97706)
        CardColor.Platinum -> Color(0xFF64748B)
        CardColor.Red -> Color(0xFFDC2626)
        CardColor.Orange -> Color(0xFFEA580C)
    }

/** The diagonal card gradient iOS draws (top left to bottom right). */
val CardColor.gradient: Brush get() = Brush.linearGradient(listOf(start, end))

@get:StringRes
val CardColor.label: Int
    get() = when (this) {
        CardColor.Black -> R.string.card_color_black
        CardColor.Purple -> R.string.card_color_purple
        CardColor.Blue -> R.string.card_color_blue
        CardColor.Green -> R.string.card_color_green
        CardColor.Gold -> R.string.card_color_gold
        CardColor.Platinum -> R.string.card_color_platinum
        CardColor.Red -> R.string.card_color_red
        CardColor.Orange -> R.string.card_color_orange
    }

@get:StringRes
val CardBrand.label: Int
    get() = when (this) {
        CardBrand.Visa -> R.string.card_brand_visa
        CardBrand.Mastercard -> R.string.card_brand_mastercard
        CardBrand.Amex -> R.string.card_brand_amex
        CardBrand.Elo -> R.string.card_brand_elo
        CardBrand.Hipercard -> R.string.card_brand_hipercard
        CardBrand.Other -> R.string.card_brand_other
    }
