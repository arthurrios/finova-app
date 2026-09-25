package com.arthurrios.finova.ui.theme

import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.arthurrios.finova.R

val Lato = FontFamily(
    Font(R.font.lato_regular, FontWeight.Normal),
    Font(R.font.lato_bold, FontWeight.Bold),
    Font(R.font.lato_black, FontWeight.Black),
)

// Mirrors Finova/Sources/Core/Constants/Fonts.swift on iOS. The iOS styles marked uppercase
// (titleSM, titleXS, title2XS) must be uppercased at the call site: Compose has no text casing
// in TextStyle.
object FinovaType {
    val TitleLG = TextStyle(fontFamily = Lato, fontSize = 28.sp, fontWeight = FontWeight.Black)
    val TitleMD = TextStyle(fontFamily = Lato, fontSize = 16.sp, fontWeight = FontWeight.Bold)
    val TitleSM = TextStyle(fontFamily = Lato, fontSize = 14.sp, fontWeight = FontWeight.Bold)
    val TitleXS = TextStyle(fontFamily = Lato, fontSize = 12.sp, fontWeight = FontWeight.Bold)
    val Title2XS = TextStyle(fontFamily = Lato, fontSize = 10.sp, fontWeight = FontWeight.Bold)
    val TextSM = TextStyle(fontFamily = Lato, fontSize = 14.sp)
    val TextSMBold = TextStyle(fontFamily = Lato, fontSize = 14.sp, fontWeight = FontWeight.Bold)
    val TextXS = TextStyle(fontFamily = Lato, fontSize = 12.sp)
    val Input = TextStyle(fontFamily = Lato, fontSize = 16.sp, lineHeight = 24.sp)
    val ButtonMD = TextStyle(
        fontFamily = Lato, fontSize = 16.sp, fontWeight = FontWeight.Bold, lineHeight = 24.sp)
    val ButtonSM = TextStyle(
        fontFamily = Lato, fontSize = 14.sp, fontWeight = FontWeight.Bold, lineHeight = 20.sp)
}
